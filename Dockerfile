# GT CPS VIP VIRTUAL MACHINE DOCKERFILE

# Collected installations:
# - Ubuntu 22.04
# - ROS 2 Jazzy
# - HELICS 3.5.1
# - GridLAB-D with HELICS integration
# - Gazebo Harmonic
# - NAV2

# BUILD DOCKER IMAGE
# docker build -t helics-docker .

# RUN DOCKER IMAGE WITH PORT MAPPING
# docker run -p 6080:80 helics-docker

# Commands to try if Docker gives errors (probably due to space/cache issues)

# docker image prune
# docker builder prune
# docker container prune

# You can also manually remove Docker images, containers, and builders in the Desktop app

# To check Docker resources

# docker system df

# UPDATE IMAGE TO GHCR

# docker tag cps-vip-vm ghcr.io/cps-vip/cps-vip-vm:latest
# docker push ghcr.io/cps-vip/cps-vip-vm:latest

# Use Tiryoh's ROS2 Desktop VNC image as the base image with Jazzy
FROM tiryoh/ros2-desktop-vnc:jazzy

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=C.UTF-8
ENV CMAKE_ARGS="-DCMAKE_CXX_STANDARD=20"

# ---- System dependencies ----
RUN apt-get update && apt-get install -y \
	locales \
	curl \
	gnupg2 \
	lsb-release \
	software-properties-common \
	libboost-dev \
	libzmq5-dev \
	git \
	cmake \
	clang-tidy \
	libxerces-c-dev \
	g++ \
	make \
	python3-pip \
	python3-venv \
	python-is-python3 \
	python3-colcon-common-extensions \
	nodejs npm \
	&& rm -rf /var/lib/apt/lists/*

# ---- Locale ----
RUN locale-gen en_US.UTF-8

# ---- ROS dev tools ----
RUN apt-get update && apt-get install -y \
	ros-dev-tools \
	ros-jazzy-desktop \
	ros-jazzy-navigation2 \
	ros-jazzy-nav2-bringup \
	ros-jazzy-nav2-minimal-tb* \
	&& rm -rf /var/lib/apt/lists/*

# ---- Gazebo Harmonic ----
RUN curl https://packages.osrfoundation.org/gazebo.gpg \
	--output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg && \
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
	http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
	| tee /etc/apt/sources.list.d/gazebo-stable.list && \
	apt-get update && \
	apt-get install -y gz-harmonic && \
	rm -rf /var/lib/apt/lists/*

# ---- Workspace dirs ----
RUN mkdir -p /home/ubuntu/software/ros2_ws/src

WORKDIR /home/ubuntu
