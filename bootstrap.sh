#!/usr/bin/env bash
# Build this ROS distribution from source.
# Sources land in ./src inside the git checkout. The checkout can live anywhere.
# The install prefix is /opt/ros/<distro>. The script does not edit shell startup files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DISTRO="$(tr -d '[:space:]' < "$ROOT/DISTRO")"
PREFIX="/opt/ros/${DISTRO}"
MAX_JOBS=16
VENV="$ROOT/.venv"

log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

ensure_install_prefix() {
  if [[ -d "$PREFIX" && -w "$PREFIX" ]]; then
    return 0
  fi
  log "Creating ${PREFIX}. The git checkout stays where it was cloned."
  sudo mkdir -p "$PREFIX"
  sudo chown -R "$(id -un):$(id -gn)" "$PREFIX"
}

# Every dialect runs mavgen into the same include/v1.0 and include/v2.0 trees.
# A parallel build interleaves those writes and installs torn headers.
serialize_mavgen() {
  local mavlink_cmake="$ROOT/src/mavlink/CMakeLists.txt"
  if [[ -f "$mavlink_cmake" ]] && ! grep -q 'mavgen.lock' "$mavlink_cmake"; then
    log "Serializing mavlink header generation. Parallel mavgen writes the same headers."
    sed -i 's#${Python_EXECUTABLE} ${mavgen_path}#/usr/bin/flock ${CMAKE_BINARY_DIR}/mavgen.lock ${Python_EXECUTABLE} ${mavgen_path}#' "$mavlink_cmake"
  fi
}

job_count() {
  local jobs="${ROS_BUILD_JOBS:-$MAX_JOBS}"
  local host
  [[ "$jobs" =~ ^[0-9]+$ ]] || die "ROS_BUILD_JOBS must be a positive integer"
  if (( jobs < 1 )); then
    die "ROS_BUILD_JOBS must be a positive integer"
  fi
  if (( jobs > MAX_JOBS )); then
    log "ROS_BUILD_JOBS=${jobs} is above the cap of ${MAX_JOBS}; using ${MAX_JOBS}"
    jobs=$MAX_JOBS
  fi
  host="$(nproc)"
  if (( jobs > host )); then
    jobs=$host
  fi
  printf '%s\n' "$jobs"
}

require_ubuntu() {
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${VERSION_ID:-}" != "24.04" && "${ALLOW_OTHER_UBUNTU:-}" != 1 ]]; then
    die "This branch builds on Ubuntu 24.04. This machine is ${PRETTY_NAME:-unknown}. Set ALLOW_OTHER_UBUNTU=1 to continue anyway."
  fi
}

require_clean_shell() {
  if [[ -n "${ROS_DISTRO:-}" ]]; then
    die "This shell already has ROS_DISTRO=${ROS_DISTRO}. Open a clean shell before building."
  fi
}

list_words() {
  awk '{ sub(/#.*/, ""); if (NF) print $1 }' "$1"
}

cmd_deps() {
  require_ubuntu
  if [[ "$(id -u)" -eq 0 ]]; then
    die "Run ./bootstrap.sh as your user. It calls sudo only for apt and GeographicLib."
  fi
  log "Installing apt packages from apt-host.txt. ROS itself is built from source, not installed from apt."
  sudo -v
  sudo apt-get update
  # shellcheck disable=SC2046
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $(list_words "$ROOT/apt-host.txt")
  if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
  fi
  "$VENV/bin/pip" install -U pip
  "$VENV/bin/pip" install -r "$ROOT/requirements.txt"
  export ROS_HOME="$ROOT/.ros"
  export ROSDEP_SOURCE_PATH="$ROOT/rosdep"
  if [[ "$DISTRO" == "noetic" ]]; then
    "$VENV/bin/rosdep" update --include-eol-distros
  else
    "$VENV/bin/rosdep" update
  fi
}

cmd_fetch() {
  command -v vcs >/dev/null || die "vcs is missing. Run ./bootstrap.sh deps first."
  mkdir -p "$ROOT/src"
  local attempt
  for attempt in 1 2 3; do
    if GIT_TERMINAL_PROMPT=0 vcs import --workers 8 --input "$ROOT/upstream.repos" "$ROOT/src"; then
      return 0
    fi
    log "vcs import failed (attempt ${attempt}). Retrying."
    sleep 2
  done
  die "vcs import failed"
}

cmd_rosdep_install() {
  [[ -d "$VENV" ]] || die "The tool environment is missing. Run ./bootstrap.sh deps first."
  [[ -d "$ROOT/src" ]] || die "src/ is missing. Run ./bootstrap.sh fetch first."
  export ROS_HOME="$ROOT/.ros"
  export ROSDEP_SOURCE_PATH="$ROOT/rosdep"
  local -a args
  args=(install --from-paths "$ROOT/src" --ignore-src --rosdistro "$DISTRO" -y
    --dependency-types buildtool --dependency-types buildtool_export
    --dependency-types build --dependency-types build_export
    --dependency-types exec)
  local skips
  # rosdep treats one --skip-keys value as a space-separated list. Separate
  # arguments would be read as source paths.
  skips="$(list_words "$ROOT/rosdep-skip.txt" | paste -sd' ' -)"
  if [[ -n "$skips" ]]; then
    args+=(--skip-keys "$skips")
  fi
  "$VENV/bin/rosdep" "${args[@]}"
}

cmd_geographiclib() {
  local marker parent
  ensure_install_prefix
  marker="$ROOT/.ros/geographiclib-datasets-installed"
  parent="$PREFIX/share/GeographicLib"
  if [[ -d "$parent/geoids" && -d "$parent/gravity" && -d "$parent/magnetic" ]]; then
    log "GeographicLib datasets were already installed under ${parent}."
    return 0
  fi
  if [[ ! -d "$ROOT/src" ]] || ! find "$ROOT/src" -path '*/mavros/package.xml' -print -quit | grep -q .; then
    log "MAVROS is not in src/; skipping GeographicLib datasets."
    return 0
  fi
  log "Installing GeographicLib datasets under ${parent}."
  mkdir -p "$parent"
  geographiclib-get-geoids -p "$parent" egm96-5
  geographiclib-get-gravity -p "$parent" egm96
  geographiclib-get-magnetic -p "$parent" emm2015
  mkdir -p "$ROOT/.ros"
  touch "$marker"
}

cmd_build() {
  require_clean_shell
  local jobs
  jobs="$(job_count)"
  export CMAKE_BUILD_PARALLEL_LEVEL="$jobs"
  export MAKEFLAGS="-j${jobs}"
  ensure_install_prefix
  log "Building ${DISTRO} into ${PREFIX} with at most ${jobs} cores."
  if [[ "$DISTRO" == "noetic" ]]; then
    [[ -x "$ROOT/src/catkin/bin/catkin_make_isolated" ]] || die "catkin is not in src/. Run ./bootstrap.sh fetch first."
    # vrpn has no package.xml, so catkin will not build it. Upstream VRPN
    # also does not install a CMake package. vrpn_client_ros uses the client
    # library, libquat, and pthread.
    vrpn_config="$PREFIX/lib/cmake/vrpn/VRPNConfig.cmake"
    if [[ ! -f "$vrpn_config" && ! -f "$PREFIX/share/vrpn/cmake/vrpn-config.cmake" && ! -f "$PREFIX/lib/libvrpn.a" ]]; then
      log "Building VRPN into ${PREFIX}."
      cmake -S "$ROOT/src/vrpn" -B "$ROOT/build/vrpn" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_TESTING=OFF
      cmake --build "$ROOT/build/vrpn" -j "$jobs"
      cmake --install "$ROOT/build/vrpn"
    fi
    if [[ ! -f "$vrpn_config" && -f "$PREFIX/lib/libvrpn.a" && -f "$PREFIX/lib/libquat.a" ]]; then
      log "Writing VRPNConfig.cmake into ${PREFIX}."
      mkdir -p "$(dirname "$vrpn_config")"
      cat > "$vrpn_config" << 'EOF'
get_filename_component(_vrpn_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(VRPN_FOUND TRUE)
set(VRPN_INCLUDE_DIR "${_vrpn_prefix}/include")
set(VRPN_INCLUDE_DIRS "${VRPN_INCLUDE_DIR}")
set(VRPN_LIBRARY "${_vrpn_prefix}/lib/libvrpn.a")
set(VRPN_LIBRARIES
  "${_vrpn_prefix}/lib/libvrpn.a"
  "${_vrpn_prefix}/lib/libquat.a"
  pthread)
EOF
    fi
    # mavlink defaults to Python 2 when this is unset. Noetic is Python 3.
    export ROS_PYTHON_VERSION=3
    # octomap 1.9.8 compiles with -Werror. GCC 13 deprecates std::iterator.
    octomap_flags="$ROOT/src/octomap/octomap/CMakeModules/CompilerSettings.cmake"
    if [[ -f "$octomap_flags" ]] && grep -q ' -Werror ' "$octomap_flags"; then
      log "Dropping -Werror from octomap so GCC 13 deprecation warnings do not fail the build."
      sed -i 's/ -Werror / -Wno-error /' "$octomap_flags"
    fi
    serialize_mavgen
    "$ROOT/src/catkin/bin/catkin_make_isolated" \
      --install \
      --install-space "$PREFIX" \
      -j"$jobs" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCATKIN_ENABLE_TESTING=OFF \
      -DPYTHON_EXECUTABLE=/usr/bin/python3
  elif [[ "$DISTRO" == "jazzy" ]]; then
    command -v colcon >/dev/null || die "colcon is missing. Run ./bootstrap.sh deps first."
    # vrpn has no package.xml. vrpn_mocap finds it through VRPNConfig.cmake.
    vrpn_config="$PREFIX/lib/cmake/vrpn/VRPNConfig.cmake"
    if [[ ! -f "$vrpn_config" && ! -f "$PREFIX/share/vrpn/cmake/vrpn-config.cmake" && ! -f "$PREFIX/lib/libvrpn.a" ]]; then
      log "Building VRPN into ${PREFIX}."
      cmake -S "$ROOT/src/vrpn" -B "$ROOT/build/vrpn" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_TESTING=OFF
      cmake --build "$ROOT/build/vrpn" -j "$jobs"
      cmake --install "$ROOT/build/vrpn"
    fi
    if [[ ! -f "$vrpn_config" && -f "$PREFIX/lib/libvrpn.a" && -f "$PREFIX/lib/libquat.a" ]]; then
      log "Writing VRPNConfig.cmake into ${PREFIX}."
      mkdir -p "$(dirname "$vrpn_config")"
      cat > "$vrpn_config" << 'EOF'
get_filename_component(_vrpn_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(VRPN_FOUND TRUE)
set(VRPN_INCLUDE_DIR "${_vrpn_prefix}/include")
set(VRPN_INCLUDE_DIRS "${VRPN_INCLUDE_DIR}")
set(VRPN_LIBRARY "${_vrpn_prefix}/lib/libvrpn.a")
set(VRPN_LIBRARIES
  "${_vrpn_prefix}/lib/libvrpn.a"
  "${_vrpn_prefix}/lib/libquat.a"
  pthread)
EOF
    fi
    serialize_mavgen
    colcon build \
      --base-paths "$ROOT/src" \
      --build-base "$ROOT/build" \
      --install-base "$PREFIX" \
      --executor sequential \
      --parallel-workers 1 \
      --symlink-install \
      --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DPython3_EXECUTABLE=/usr/bin/python3
  else
    die "Unknown DISTRO ${DISTRO}"
  fi
}

cmd_smoke() {
  [[ -f "$PREFIX/setup.bash" ]] || die "${PREFIX}/setup.bash was not produced."
  bash --noprofile --norc -c '
    set -eu
    set +u
    # shellcheck disable=SC1090
    source "$1"
    distro=$2
    if [[ "$distro" == noetic ]]; then
      test "$(rosversion -d)" = noetic
      rospack find mavros >/dev/null
      rospack find vrpn_client_ros >/dev/null
      rospack find cv_bridge >/dev/null
      rospack find pcl_ros >/dev/null
    else
      test "$ROS_DISTRO" = jazzy
      ros2 pkg prefix mavros >/dev/null
      ros2 pkg prefix vrpn_mocap >/dev/null
      ros2 pkg prefix cv_bridge >/dev/null
      ros2 pkg prefix rviz2 >/dev/null
    fi
  ' bash "$PREFIX/setup.bash" "$DISTRO"
  log "Smoke check passed for ${DISTRO}."
  log "Load this checkout when you need it: source env.bash"
  log "Shell startup files were not modified."
}

cmd_gazebo() {
  if [[ "$DISTRO" != noetic ]]; then
    return 0
  fi
  if [[ "${XGC2_SKIP_GAZEBO:-}" == 1 ]]; then
    log "Skipping Gazebo Classic."
    return 0
  fi
  if [[ ! -x "$ROOT/gazebo/bootstrap.sh" ]]; then
    log "gazebo/bootstrap.sh is missing. Initialize the gazebo submodule to install Gazebo Classic."
    return 0
  fi
  local gz_prefix="${XGC2_GAZEBO_PREFIX:-$PREFIX/opt/gazebo}"
  mkdir -p "$gz_prefix"
  XGC2_GAZEBO_PREFIX="$gz_prefix" "$ROOT/gazebo/bootstrap.sh"
  mkdir -p "$PREFIX/etc/catkin/profile.d"
  cp "$ROOT/gazebo/prefix.sh" "$PREFIX/etc/catkin/profile.d/99-xgc2-gazebo.sh"
}

usage() {
  cat <<EOF
Usage: ./bootstrap.sh [all|deps|fetch|build|refresh-pins]

  all           toolchain, source download, dependencies, build, Gazebo Classic (default)
  deps          apt toolchain and rosdep
  fetch         clone the pinned sources into ./src
  build         install library dependencies, compile, smoke check, Gazebo Classic
  refresh-pins  rewrite upstream.repos from packages.txt

Gazebo Classic installs to ${PREFIX}/opt/gazebo when the gazebo submodule is present.
Set XGC2_SKIP_GAZEBO=1 to build Noetic without it.

Compilation uses at most ${MAX_JOBS} cores. Set ROS_BUILD_JOBS to a smaller number if you want.
If a build stops, run ./bootstrap.sh build to continue it.
EOF
}

main() {
  local cmd="${1:-all}"
  case "$cmd" in
    all)
      cmd_deps
      cmd_fetch
      cmd_rosdep_install
      cmd_geographiclib
      cmd_build
      cmd_smoke
      cmd_gazebo
      ;;
    deps) cmd_deps ;;
    fetch) cmd_fetch ;;
    build)
      cmd_rosdep_install
      cmd_geographiclib
      cmd_build
      cmd_smoke
      cmd_gazebo
      ;;
    refresh-pins)
      cmd_deps
      "$VENV/bin/python" "$ROOT/scripts/refresh-upstream.py"
      ;;
    -h|--help|help) usage ;;
    *)
      usage
      die "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
