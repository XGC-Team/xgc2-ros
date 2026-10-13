# Building ROS 1 Noetic from source

On Ubuntu 24.04 this downloads the Noetic sources into `src/` in this directory and installs the build into `/opt/ros/noetic`. The repository can be cloned to any path. Git does not store those sources.

```bash
git clone --recurse-submodules -b noetic --single-branch https://github.com/XGC-Team/xgc2-ros.git ros/noetic
cd ros/noetic
./bootstrap.sh
source env.bash
```

`./bootstrap.sh` asks for sudo. It installs the compiler toolchain and the system libraries, creates `/opt/ros/noetic`, and installs the GeographicLib datasets that MAVROS needs. ROS packages are built from `src/` in this directory into `/opt/ros/noetic`. It does not install the `ros-noetic-*` or `ros-one-*` binary packages. Leave `source env.bash` out of `~/.bashrc`.

The build uses at most 16 cores. To use fewer:

```bash
ROS_BUILD_JOBS=8 ./bootstrap.sh
```

To continue after an interruption:

```bash
./bootstrap.sh build
```

## What this branch contains

The default set covers everyday messages, tf, RViz, rqt, image and camera packages, PCL, laser, MAVROS, the VRPN client, `robot_state_publisher`, the commonly used controllers from ros_control, octomap, diagnostics, `foxglove_msgs`, `ros_babel_fish`, `rosfmt`, `serial`, and `gtsam`. The package list is `packages.txt`. The pinned commits are in `upstream.repos`.

Some official Noetic repositories do not build on Ubuntu 24.04. Those repositories use the Noetic continuation patches from [ROS-O](https://github.com/ros-o), and the commit ids are in `upstream.repos`. `ros_environment` stays on the Noetic distribution, so `ROS_DISTRO` is `noetic` after the environment is loaded.

Gazebo Classic 11 is the `gazebo` submodule, the `noble-gz11` branch of [xgc2-gazebo](https://github.com/XGC-Team/xgc2-gazebo). `./bootstrap.sh` installs it to `/opt/ros/noetic/opt/gazebo` and does not write it under `/usr`. `gazebo_ros` is absent from `packages.txt`, so the Noetic build does not depend on this Gazebo. After `source /opt/ros/noetic/setup.bash`, `gazebo` and `gz` come from that prefix. Load this environment in its own shell, separate from a ROS 2 environment.

The following is outside the default build:

- `jsk_rviz_plugins` pulls in `jsk_recognition`, which does not build reliably on 24.04. To include it, add the package name to `packages.txt` and run `./bootstrap.sh refresh-pins`.

VRPN uses the source packages `vrpn` and `vrpn_client_ros`. Ubuntu 24.04 has no `libvrpn-dev`.

## Packages

On Focal the official package for this role is `ros-noetic-desktop-full`. Ubuntu 24.04 does not have that package. The workflow on `main` builds this branch and Gazebo Classic in parallel on a clean Ubuntu 24.04 and produces `xgc2-ros-noetic` for amd64 and arm64. Inside the package, Gazebo Classic is at `/opt/ros/noetic/opt/gazebo`.

After downloading the deb that matches this machine:

```bash
sudo apt install ./xgc2-ros-noetic_<version>_<arch>.deb
source /opt/ros/noetic/setup.bash
```

Leave that `source` line out of `~/.bashrc`. Cloning locally and running `./bootstrap.sh` still works. That is a separate path, and CI leaves it alone.

Update the lock files:

```bash
./bootstrap.sh refresh-pins
```
