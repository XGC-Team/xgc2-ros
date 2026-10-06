# xgc2-ros

Ubuntu 24.04 上从源码构建 ROS 的脚本仓库。每个 ROS 版本是一个独立分支。Git 里只有工具脚本和源码锁定文件，不保存 ROS 源码。

克隆哪个分支，源码就下载到那个工作副本里面的 `src/`，编译结果放在同一副本的 `install/`。脚本只用仓库根目录的相对路径。

不要把 `source env.bash` 写进 `~/.bashrc`。需要哪个版本，就在那个目录里加载。

```bash
git clone -b noetic --single-branch git@github.com:XGC-Team/xgc2-ros.git ros/noetic
git clone -b jazzy --single-branch git@github.com:XGC-Team/xgc2-ros.git ros/jazzy

cd ros/noetic
./bootstrap.sh

cd ../jazzy
./bootstrap.sh
```

`./bootstrap.sh` 会用 sudo 安装编译工具链和系统库，然后下载、配置并编译。ROS 本体不会从 apt 安装 `ros-noetic-*` 或 `ros-jazzy-*`。

每个版本的编译最多使用 16 核。两个目录可以同时构建，各自封顶 16 核。要降低占用时设置 `ROS_BUILD_JOBS`。

构建完成后：

```bash
source env.bash
```

分支说明：

| 分支 | 内容 |
| --- | --- |
| `main` | 本说明 |
| `noetic` | ROS 1 Noetic |
| `jazzy` | ROS 2 Jazzy |
