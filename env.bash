# Load this checkout's ROS install into the current shell.
# Usage: source env.bash
# Do not add this file to a shell startup file.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '%s\n' "source env.bash" >&2
  exit 1
fi

_xgc2_ros_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_xgc2_ros_distro="$(tr -d '[:space:]' < "${_xgc2_ros_root}/DISTRO")"
_xgc2_ros_prefix="/opt/ros/${_xgc2_ros_distro}"
if [[ -d "${_xgc2_ros_prefix}/share/GeographicLib" ]]; then
  export GEOGRAPHICLIB_DATA="${_xgc2_ros_prefix}/share/GeographicLib"
fi
if [[ ! -f "${_xgc2_ros_prefix}/setup.bash" ]]; then
  printf '%s\n' "${_xgc2_ros_prefix}/setup.bash is missing. From this directory run ./bootstrap.sh" >&2
  unset _xgc2_ros_root _xgc2_ros_distro _xgc2_ros_prefix
  return 1
fi

_xgc2_ros_nounset=0
case $- in
  *u*) _xgc2_ros_nounset=1 ;;
esac
set +u
# shellcheck disable=SC1091
source "${_xgc2_ros_prefix}/setup.bash"
if [[ "${_xgc2_ros_nounset}" -eq 1 ]]; then
  set -u
fi
unset _xgc2_ros_root _xgc2_ros_distro _xgc2_ros_prefix _xgc2_ros_nounset
