# xgc2-ros

Scripts for using ROS on Ubuntu 24.04. Git stores the helper scripts and the source lock files. The ROS source tree stays out of Git.

## Install Noetic

On Ubuntu 20.04 the package for this role is `ros-noetic-desktop-full`. Ubuntu 24.04 does not publish that package.

The “Noetic on Ubuntu 24.04” workflow in Actions is started by hand. On a clean Ubuntu 24.04 it builds Noetic and Gazebo Classic side by side, on both amd64 and arm64, packs the two into an `xgc2-ros-noetic` deb for each architecture, and publishes the debs to [Releases](https://github.com/XGC-Team/xgc2-ros/releases). Gazebo Classic is placed at `/opt/ros/noetic/opt/gazebo`, outside `/usr`. After `source /opt/ros/noetic/setup.bash`, that prefix supplies Gazebo.

Download the deb that matches this machine's architecture:

```bash
sudo apt install ./xgc2-ros-noetic_<version>_<arch>.deb
source /opt/ros/noetic/setup.bash
```

Leave that `source` line out of `~/.bashrc`.

## Build it yourself

Clone the repository to any path. Sources stay in `src/` inside the working copy. The Noetic build installs into `/opt/ros/noetic`. A local build and the CI workflow above are separate paths.

```bash
git clone --recurse-submodules -b noetic --single-branch https://github.com/XGC-Team/xgc2-ros.git ros/noetic
cd ros/noetic
./bootstrap.sh
source env.bash
```

`gazebo` is the `noble-gz11` branch of the [xgc2-gazebo](https://github.com/XGC-Team/xgc2-gazebo) submodule. The Noetic package list does not compile Gazebo, so the two builds can run at the same time. After installation, Gazebo Classic is at `/opt/ros/noetic/opt/gazebo`.

`./bootstrap.sh` uses sudo to install the compiler toolchain and the system libraries. The build uses at most 16 cores.

ROS 2 Jazzy comes from the official apt packages and stays outside this workflow. Add the Ubuntu 24.04 ROS 2 apt source as the ROS 2 documentation describes, then install `ros-jazzy-desktop-full`.

| Branch | Contents |
| --- | --- |
| `main` | This document, and the Noetic workflow for both architectures |
| `noetic` | ROS 1 Noetic |
| `jazzy` | A ROS 2 Jazzy source tree for reading the code |
