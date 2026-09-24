# cps-cosimulation-env

## Installation
Prerequisites: Docker is installed. You may need to prefix with `sudo` if the docker group is not properly set up.

1. Build the Dockerfile
    - `docker build -t cps_cosim .`

2. Start a container with proper mounting
    - ``docker run -d -v `pwd`/software:/home/ubuntu/software -p 8060:80 --name cps cps_cosim``

3. Copy the install script into the docker container from your local machine by running `docker cp install_software.sh cps:/home/ubuntu`

4. Log into the VNC session
    - Go to `localhost:8060` in the browser
    - username: ubuntu
    - password: ubuntu

5. Run the installation script to get HELICS and GridLAB-D and this repo
    ```bash
    # inside the running container
    chmod +x ./install_software.sh
    ./install_software.sh
    ```
    - It is okay for some modules to fail to compile in `colcon`; we only need the minimal publisher and subscriber to work for this demo
    - Many warning messages is also expected behavior during this script

6. Run the basic transmission/relay simulator code (no fault injection)
    ```bash
    cd ~/cosim-fault-injection/simple_gridlabd_example
    sh ./run_example.sh

    # when finished:
    sh ./kill_all.sh
    ```

7. Run the simulator with fault injection (using a different launch script)
    1. Run the example with the control center added
    ```bash
    cd ~/cosim-fault-injection/simple_gridlabd_example
    sh ./run_example_cc.sh

    # when finished:
    sh ./kill_all.sh
    ```

    2. In a new terminal, build the updated example code and run the publisher

    ```bash
    cd ~/ros2_ws
    source install/setup.bash

    # build the example 
    colcon build --packages-select examples_rclcpp_minimal_publisher

    ros2 run examples_rclcpp_minimal_publisher publisher_member_function
    ```

    3. In a third terminal, run the subscriber example
    ```bash
    cd ~/ros2_ws
    source install/setup.bash
    ros2 run examples_rclcpp_minimal_subscriber subscriber_member_function
    ```