#!/usr/bin/env bash
# Build this ROS distribution from source into this checkout.
# Sources land in ./src. The install prefix is ./install.
# Paths are relative to this checkout. The script does not edit shell startup files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DISTRO="$(tr -d '[:space:]' < "$ROOT/DISTRO")"
MAX_JOBS=16
VENV="$ROOT/.venv"

log() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

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
  log "Installing the host toolchain with sudo. ROS itself is built from source, not installed from apt."
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
  args=(install --from-paths "$ROOT/src" --ignore-src --rosdistro "$DISTRO" -y)
  local skips
  skips="$(list_words "$ROOT/rosdep-skip.txt" | paste -sd' ' -)"
  if [[ -n "$skips" ]]; then
    # shellcheck disable=SC2206
    args+=(--skip-keys $skips)
  fi
  "$VENV/bin/rosdep" "${args[@]}"
}

cmd_geographiclib() {
  local script marker
  marker="$ROOT/.ros/geographiclib-datasets-installed"
  if [[ -f "$marker" ]]; then
    log "GeographicLib datasets were already installed for this checkout."
    return 0
  fi
  script="$(find "$ROOT/src" -path '*/mavros/scripts/install_geographiclib_datasets.sh' -print -quit || true)"
  if [[ -z "$script" ]]; then
    log "MAVROS GeographicLib installer was not found; skipping datasets."
    return 0
  fi
  log "Installing GeographicLib datasets used by MAVROS."
  sudo -v
  sudo bash "$script"
  mkdir -p "$ROOT/.ros"
  touch "$marker"
}

cmd_build() {
  require_clean_shell
  local jobs
  jobs="$(job_count)"
  export CMAKE_BUILD_PARALLEL_LEVEL="$jobs"
  export MAKEFLAGS="-j${jobs}"
  log "Building ${DISTRO} with at most ${jobs} cores."
  if [[ "$DISTRO" == "noetic" ]]; then
    [[ -x "$ROOT/src/catkin/bin/catkin_make_isolated" ]] || die "catkin is not in src/. Run ./bootstrap.sh fetch first."
    "$ROOT/src/catkin/bin/catkin_make_isolated" \
      --install \
      --install-space "$ROOT/install" \
      -j"$jobs" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCATKIN_ENABLE_TESTING=OFF \
      -DPYTHON_EXECUTABLE=/usr/bin/python3
  elif [[ "$DISTRO" == "jazzy" ]]; then
    command -v colcon >/dev/null || die "colcon is missing. Run ./bootstrap.sh deps first."
    colcon build \
      --base-paths "$ROOT/src" \
      --build-base "$ROOT/build" \
      --install-base "$ROOT/install" \
      --executor sequential \
      --parallel-workers 1 \
      --symlink-install \
      --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DPython3_EXECUTABLE=/usr/bin/python3
  else
    die "Unknown DISTRO ${DISTRO}"
  fi
}

cmd_smoke() {
  [[ -f "$ROOT/install/setup.bash" ]] || die "install/setup.bash was not produced."
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
  ' bash "$ROOT/install/setup.bash" "$DISTRO"
  log "Smoke check passed for ${DISTRO}."
  log "Load this checkout when you need it: source env.bash"
  log "Shell startup files were not modified."
}

usage() {
  cat <<EOF
Usage: ./bootstrap.sh [all|deps|fetch|build|refresh-pins]

  all           toolchain, source download, dependencies, build (default)
  deps          apt toolchain and rosdep
  fetch         clone the pinned sources into ./src
  build         install library dependencies, compile, smoke check
  refresh-pins  rewrite upstream.repos from packages.txt

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
      ;;
    deps) cmd_deps ;;
    fetch) cmd_fetch ;;
    build)
      cmd_rosdep_install
      cmd_geographiclib
      cmd_build
      cmd_smoke
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
