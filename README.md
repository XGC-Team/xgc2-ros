# ROS 2 Jazzy 源码构建

在 Ubuntu 24.04 上把 Jazzy 源码下载到本目录的 `src/` 并安装到 `install/`。Git 不保存这些源码。

```bash
git clone -b jazzy --single-branch git@github.com:XGC-Team/xgc2-ros.git ros/jazzy
cd ros/jazzy
./bootstrap.sh
source env.bash
```

`./bootstrap.sh` 会请求 sudo，用来安装编译工具链、系统依赖库，以及 MAVROS 需要的 GeographicLib 数据集。ROS 包本身在本目录编译，不安装 `ros-jazzy-*` 二进制包。不要把 `source env.bash` 写进 `~/.bashrc`。

编译最多使用 16 核，包是一个一个编的，每个包内部使用这些核。需要更少时：

```bash
ROS_BUILD_JOBS=8 ./bootstrap.sh
```

中断后继续编译：

```bash
./bootstrap.sh build
```

## 这个分支包含什么

默认覆盖 `ros_base`、RViz、rqt、图像与相机、PCL、激光、MAVROS、`vrpn_mocap`、`rmw_cyclonedds_cpp`、octomap，以及 `ros_gz`（Gazebo Harmonic）。包名单在 `packages.txt`，具体检出提交在 `upstream.repos`。

`rmw_connextdds` 依赖 RTI Connext，默认不拉取。Fast DDS 随 `ros_base` 一起构建，Cyclone DDS 按上面的包加入。环境变量不会被脚本改写；要用 Cyclone DDS 时自己导出 `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`。

`rosidl_generator_rs` 默认不拉取。装上它之后，编译消息包会生成 Rust 代码，还要准备 rustc。C、C++、Python 的接口生成不依赖它。代码检查用的 `uncrustify_vendor` 也不在默认清单里。

`ros_gz` 会在编译时拉取 Gazebo Harmonic 的 vendor 源码，占用的磁盘和时间都比 Noetic 分支大。

更新锁定文件：

```bash
./bootstrap.sh refresh-pins
```
