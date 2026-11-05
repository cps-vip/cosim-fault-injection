#!/bin/bash
echo "Stopping all simulation, power grid, and ROS 2 processes..."
pkill -f 'helics_broker|gz sim|gridlabd|Relay_simulator|Transmission_simulator|CC_simulator|waypoint_publisher|twist_mux|robot_state_publisher|nav2_' 2>/dev/null || true
pkill -9 -f 'helics_broker|gridlabd' 2>/dev/null || true
echo "Done."
