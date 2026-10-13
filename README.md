# Building ROS 2 Jazzy from source

On Ubuntu 24.04 this downloads the Jazzy sources into `src/` in this directory and installs them into `install/`. Git does not store those sources.

```bash
git clone -b jazzy --single-branch git@github.com:XGC-Team/xgc2-ros.git ros/jazzy
cd ros/jazzy
./bootstrap.sh
source env.bash
```

`./bootstrap.sh` asks for sudo. It installs the compiler toolchain, the system libraries, and the GeographicLib datasets that MAVROS needs. The ROS packages themselves are built in this directory. It does not install the `ros-jazzy-*` binary packages. Leave `source env.bash` out of `~/.bashrc`.

The build uses at most 16 cores. Packages are built one at a time, and each package uses those cores internally. To use fewer:

```bash
ROS_BUILD_JOBS=8 ./bootstrap.sh
```

To continue after an interruption:

```bash
./bootstrap.sh build
```

## What this branch contains

The default set covers `ros_base`, RViz, rqt, image and camera packages, PCL, laser, MAVROS, `vrpn_mocap`, `rmw_cyclonedds_cpp`, octomap, and `ros_gz` (Gazebo Harmonic). The package list is `packages.txt`. The pinned commits are in `upstream.repos`.

`rmw_connextdds` depends on RTI Connext and is left out of the default fetch. Fast DDS is built together with `ros_base`. Cyclone DDS is included through the package named above. The script leaves environment variables unchanged. To use Cyclone DDS, export `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` yourself.

`rosidl_generator_rs` is left out of the default fetch. Once it is installed, building message packages generates Rust code, which needs rustc. C, C++, and Python interface generation do not depend on it. `uncrustify_vendor`, used for code checks, is also absent from the default list.

At build time `ros_gz` fetches the Gazebo Harmonic vendor sources. That takes more disk and more time than the Noetic branch.

Update the lock files:

```bash
./bootstrap.sh refresh-pins
```
