#!/bin/bash

mkdir -p results/
TIMESTAMP=$(date +%s)

BROKER_LOG="./results/broker_$TIMESTAMP.log"
TRANSMISSION_LOG="./results/TransmissionSim_$TIMESTAMP.log"
CC_LOG="./results/CCSim_$TIMESTAMP.log"
DISTRIBUTION_LOG="./results/DistributionSim_$TIMESTAMP.log"
RELAY_LOG="./results/RelaySim_$TIMESTAMP.log"
NAV2_LOG="./results/NAV2_$TIMESTAMP.log"
GAZEBO_LOG="./results/Gazebo_$TIMESTAMP.log"
ROS2_LOG="./results/ROS2_$TIMESTAMP.log"

touch $BROKER_LOG
touch $TRANSMISSION_LOG
touch $DISTRIBUTION_LOG
touch $CC_LOG
touch $RELAY_LOG
touch $NAV2_LOG
touch $GAZEBO_LOG
touch $ROS2_LOG

uv sync

# Source ROS2 setup
source /opt/ros/humble/setup.bash

HELICS_BROKER=`which helics_broker`
($HELICS_BROKER -t="zmq" --federates=5 --name=mainbroker > $BROKER_LOG)&

# Start Gazebo, NAV2, and robot via comprehensive launch file
echo "Starting Gazebo, NAV2 stack, and robot..."
ros2 launch vipnav launch_sim.launch.py headless:=true > $GAZEBO_LOG 2>&1 &
NAV2_PID=$!

# Wait for NAV2 action server to be ready (can take 15-30 seconds)
echo "Waiting for NAV2 action server to become available..."
for i in {1..60}; do
  if ros2 service list 2>/dev/null | grep -q "navigate_to_pose"; then
    echo "NAV2 action server is ready!"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "WARNING: NAV2 action server did not become available after 60 seconds"
  fi
  sleep 1
done

# Start grid and power simulators
cd Transmission
uv run Transmission_simulator.py > ../$TRANSMISSION_LOG 2>&1 &
cd ..

cd CC
uv run CC_simulator.py > ../$CC_LOG 2>&1 &
cd ..

cd Distribution
gridlabd IEEE_123_feeder_0.glm > ../$DISTRIBUTION_LOG 2>&1 &
cd ..

cd Relay 
uv run Relay_simulator.py > ../$RELAY_LOG 2>&1 &
cd ..

# Start ROS2 minimal publisher (HELICS federate for NAV2)
echo "Starting ROS2 HELICS federate..."
ros2 run examples_rclcpp_minimal_publisher publisher_member_function > $ROS2_LOG 2>&1 &

echo "All simulators and ROS2 services started!"
echo "NAV2/Gazebo/Robot PID: $NAV2_PID"
echo "Logs available in results/ directory"
echo ""
echo "To stop all services, run: pkill -f 'helics_broker|gz|ros2|gridlabd|python'; sleep 2"
