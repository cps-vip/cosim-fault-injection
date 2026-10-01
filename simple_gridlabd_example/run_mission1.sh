#!/usr/bin/env bash
# ==============================================================================
# Unified Co-Simulation & NAV2 Runner for Mission 1
# ==============================================================================
# This script eliminates manual multi-terminal steps by launching:
# 1. HELICS Broker (5 federates)
# 2. Gazebo simulation, Robot, SLAM, and Waypoint Publisher (launch_sim)
# 3. Nav2 Navigation Stack (navigation_launch)
# 4. Power Grid Co-simulators (Transmission, Distribution, Relay, Control Center)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse optional arguments
HEADLESS="false"
for arg in "$@"; do
    case $arg in
        --headless)
            HEADLESS="true"
            shift
            ;;
    esac
done

echo "============================================================"
echo " Starting CPS Mission 1 Unified Co-Simulation"
echo " Headless mode: $HEADLESS"
echo "============================================================"

# ------------------------------------------------------------------------------
# 1. Environment & Sourcing Detection
# ------------------------------------------------------------------------------
# Detect ROS 2 distro
if [ -f "/opt/ros/jazzy/setup.bash" ]; then
    source /opt/ros/jazzy/setup.bash
    echo "[INFO] Sourced ROS 2 Jazzy"
elif [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
    echo "[INFO] Sourced ROS 2 Humble"
else
    echo "[WARN] No standard /opt/ros/<distro>/setup.bash found. Relying on existing environment."
fi

# Detect ROS 2 workspace
if [ -f "$PROJECT_ROOT/NAV2/install/setup.bash" ]; then
    source "$PROJECT_ROOT/NAV2/install/setup.bash"
    echo "[INFO] Sourced workspace from $PROJECT_ROOT/NAV2"
elif [ -f "$HOME/ros2_ws/install/setup.bash" ]; then
    source "$HOME/ros2_ws/install/setup.bash"
    echo "[INFO] Sourced workspace from $HOME/ros2_ws"
fi

# Ensure python dependencies are synced
if command -v uv &>/dev/null; then
    (cd "$SCRIPT_DIR/.." && uv sync 2>/dev/null || true)
fi

# Detect co-sim virtual environment site-packages and export to PYTHONPATH
VENV_SITE=$(find "$SCRIPT_DIR/.." -maxdepth 4 -type d -path "*/.venv/lib/python*/site-packages" 2>/dev/null | head -n 1)
if [ -n "$VENV_SITE" ]; then
    export PYTHONPATH="$VENV_SITE:${PYTHONPATH:-}"
    echo "[INFO] Added venv site-packages to PYTHONPATH: $VENV_SITE"
fi

# ------------------------------------------------------------------------------
# 2. Setup Logging and Process Tracking
# ------------------------------------------------------------------------------
mkdir -p "$SCRIPT_DIR/results"
TIMESTAMP=$(date +%s)
PIDS=()

cleanup() {
    echo ""
    echo "============================================================"
    echo " Stopping all simulators and ROS 2 nodes..."
    echo "============================================================"
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -SIGTERM "$pid" 2>/dev/null || true
        fi
    done
    sleep 1
    # Fallback cleanup for any child or orphaned processes
    pkill -f 'helics_broker|gz sim|gridlabd|Relay_simulator|Transmission_simulator|CC_simulator' 2>/dev/null || true
    echo "[INFO] All processes stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ------------------------------------------------------------------------------
# 3. Start HELICS Broker (5 federates expected)
# ------------------------------------------------------------------------------
# Federates:
# 1. TransmissionFederate
# 2. GridLABDFederate
# 3. RelayFederate
# 4. CCFederate
# 5. Robot_Bridge_Fed (waypoint_publisher)
echo "[1/4] Starting HELICS broker (5 federates)..."
HELICS_BROKER=$(command -v helics_broker || echo "helics_broker")
$HELICS_BROKER -t="zmq" --federates=5 --name=mainbroker > "$SCRIPT_DIR/results/broker_$TIMESTAMP.log" 2>&1 &
PIDS+=($!)
sleep 1

# ------------------------------------------------------------------------------
# 4. Start Core Simulation (Gazebo, Robot, SLAM, Waypoint Publisher)
# ------------------------------------------------------------------------------
echo "[2/4] Launching Gazebo, Robot, SLAM, and Waypoint Publisher..."
ros2 launch vipnav launch_sim.launch.py headless:="$HEADLESS" > "$SCRIPT_DIR/results/sim_core_$TIMESTAMP.log" 2>&1 &
PIDS+=($!)

# ------------------------------------------------------------------------------
# 5. Start Nav2 Navigation Stack
# ------------------------------------------------------------------------------
echo "[3/4] Launching Nav2 stack..."
ros2 launch vipnav navigation_launch.py use_sim_time:=True > "$SCRIPT_DIR/results/nav2_$TIMESTAMP.log" 2>&1 &
PIDS+=($!)

# Wait for Nav2 action server to be ready before injecting faults
echo "Waiting for Nav2 action server (/navigate_to_pose)..."
READY=0
for i in {1..45}; do
    if ros2 service list 2>/dev/null | grep -q "navigate_to_pose"; then
        READY=1
        echo " -> Nav2 action server is ready!"
        break
    fi
    sleep 1
done

if [ $READY -eq 0 ]; then
    echo "[WARN] Nav2 action server wait timed out (45s). Launching grid simulators anyway."
fi

# ------------------------------------------------------------------------------
# 6. Start Grid & Power Simulators (Co-Simulation)
# ------------------------------------------------------------------------------
echo "[4/4] Starting GridLAB-D, PyPower Transmission, Relay, and Control Center..."

(cd "$SCRIPT_DIR/Transmission" && uv run Transmission_simulator.py > "$SCRIPT_DIR/results/Transmission_$TIMESTAMP.log" 2>&1) &
PIDS+=($!)

(cd "$SCRIPT_DIR/Distribution" && gridlabd IEEE_123_feeder_0.glm > "$SCRIPT_DIR/results/Distribution_$TIMESTAMP.log" 2>&1) &
PIDS+=($!)

(cd "$SCRIPT_DIR/Relay" && uv run Relay_simulator.py > "$SCRIPT_DIR/results/Relay_$TIMESTAMP.log" 2>&1) &
PIDS+=($!)

(cd "$SCRIPT_DIR/CC" && uv run CC_simulator.py > "$SCRIPT_DIR/results/CC_$TIMESTAMP.log" 2>&1) &
PIDS+=($!)

echo "============================================================"
echo " Co-Simulation is running successfully!"
echo " Logs are streaming to: $SCRIPT_DIR/results/"
echo " Press [Ctrl+C] to gracefully stop all processes."
echo "============================================================"

# Keep script running and wait for background processes
wait
