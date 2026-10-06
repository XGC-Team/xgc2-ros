# ROS 1 Noetic 源码构建

在 Ubuntu 24.04 上把 Noetic 源码下载到本目录的 `src/`，编译结果安装到 `/opt/ros/noetic`。仓库可以克隆到任意路径。Git 不保存这些源码。

```bash
git clone -b noetic --single-branch git@github.com:XGC-Team/xgc2-ros.git ros/noetic
cd ros/noetic
./bootstrap.sh
source env.bash
```

`./bootstrap.sh` 会请求 sudo，用来安装编译工具链、系统依赖库，创建 `/opt/ros/noetic`，以及 MAVROS 需要的 GeographicLib 数据集。ROS 包从本目录的 `src/` 编译进 `/opt/ros/noetic`，不安装 `ros-noetic-*` 或 `ros-one-*` 二进制包。不要把 `source env.bash` 写进 `~/.bashrc`。

编译最多使用 16 核。需要更少时：

```bash
ROS_BUILD_JOBS=8 ./bootstrap.sh
```

中断后继续编译：

```bash
./bootstrap.sh build
```

## 这个分支包含什么

默认覆盖日常使用的消息、tf、RViz、rqt、图像与相机、PCL、激光、MAVROS、VRPN client、`robot_state_publisher`、ros_control 里常用的控制器、octomap、diagnostics、`foxglove_msgs`、`ros_babel_fish`、`rosfmt`、`serial`、`gtsam`。包名单在 `packages.txt`，具体检出提交在 `upstream.repos`。

Ubuntu 24.04 的官方 Noetic 源码有一批仓库编不过。这些仓库改用 [ROS-O](https://github.com/ros-o) 的 Noetic 延续补丁，提交号写在 `upstream.repos` 里。`ros_environment` 仍使用 Noetic 发行版，加载后 `ROS_DISTRO` 是 `noetic`。

下面两项不在默认构建里：

- Gazebo Classic 11 不在 Ubuntu 24.04 的软件源中，所以没有放入 `gazebo_ros`。Jazzy 分支使用 `ros_gz`。
- `jsk_rviz_plugins` 会带上 `jsk_recognition`，在 24.04 上不能稳定编过。需要时把包名加进 `packages.txt`，再运行 `./bootstrap.sh refresh-pins`。

VRPN 使用源码包 `vrpn` 和 `vrpn_client_ros`。Ubuntu 24.04 没有 `libvrpn-dev`。

## 安装包

Focal 上同角色的官方包叫 `ros-noetic-desktop-full`。Ubuntu 24.04 没有这个包。`main` 分支上的工作流会在干净的 Ubuntu 24.04 里编译本分支，打出 amd64 和 arm64 的 `xgc2-ros-noetic`。Gazebo Classic 不在包里。

下载和本机架构一致的 deb 后：

```bash
sudo apt install ./xgc2-ros-noetic_<版本>_<架构>.deb
source /opt/ros/noetic/setup.bash
```

不要把 `source` 写进 `~/.bashrc`。本地克隆后运行 `./bootstrap.sh` 仍然可以，那是另一条路，不会被 CI 改写。

更新锁定文件：

```bash
./bootstrap.sh refresh-pins
```
