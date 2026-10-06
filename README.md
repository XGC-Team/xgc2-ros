# xgc2-ros

Ubuntu 24.04 上使用 ROS 的脚本仓库。Git 里只有工具脚本和源码锁定文件，不保存 ROS 源码。

## 安装 Noetic

Ubuntu 20.04 上同角色的官方包叫 `ros-noetic-desktop-full`。Ubuntu 24.04 没有这个包。

Actions 里的 “Noetic on Ubuntu 24.04” 可以手动触发。它在干净的 Ubuntu 24.04 上并行编译 Noetic 和 Gazebo Classic，各跑 amd64 和 arm64，再把两者打进 `xgc2-ros-noetic`，发到 [Releases](https://github.com/XGC-Team/xgc2-ros/releases)。Gazebo Classic 位于 `/opt/ros/noetic/opt/gazebo`，不安装到 `/usr`。`source /opt/ros/noetic/setup.bash` 之后使用这份 Gazebo。

下载和本机架构一致的 deb：

```bash
sudo apt install ./xgc2-ros-noetic_<版本>_<架构>.deb
source /opt/ros/noetic/setup.bash
```

不要把 `source` 写进 `~/.bashrc`。

## 自己编译

仓库可以克隆到任意路径。源码留在工作副本的 `src/`，Noetic 的编译结果安装到 `/opt/ros/noetic`。这条路和上面的 CI 互不替代。

```bash
git clone --recurse-submodules -b noetic --single-branch https://github.com/XGC-Team/xgc2-ros.git ros/noetic
cd ros/noetic
./bootstrap.sh
source env.bash
```

`gazebo` 是子仓库 [xgc2-gazebo](https://github.com/XGC-Team/xgc2-gazebo) 的 `noble-gz11`。Noetic 的包名单不编译 Gazebo，所以两条构建可以并行。装好后 Gazebo Classic 在 `/opt/ros/noetic/opt/gazebo`。

`./bootstrap.sh` 会用 sudo 安装编译工具链和系统库。编译最多 16 核。

ROS 2 Jazzy 使用官方 apt 包，不在这个工作流里重编。需要先按 ROS 2 的说明添加 Ubuntu 24.04 软件源，然后安装 `ros-jazzy-desktop-full`。

| 分支 | 内容 |
| --- | --- |
| `main` | 本说明，以及 Noetic 的双架构工作流 |
| `noetic` | ROS 1 Noetic |
| `jazzy` | ROS 2 Jazzy 的源码阅读副本 |
