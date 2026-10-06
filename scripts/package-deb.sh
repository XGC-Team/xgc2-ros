#!/usr/bin/env bash
# Package /opt/ros/noetic into dist/xgc2-ros-noetic_<version>_<arch>.deb.
# The Focal metapackage with this role is ros-noetic-desktop-full. Noble has no such package.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="/opt/ros/noetic"
version="${XGC2_DEB_VERSION:-}"

if [[ ! "$version" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]]; then
  printf '%s\n' "Set XGC2_DEB_VERSION to a Debian version, for example 1.0.0+noble.1" >&2
  exit 1
fi
[[ -f "$PREFIX/setup.bash" ]] || {
  printf '%s\n' "${PREFIX}/setup.bash is missing. Build Noetic before packaging." >&2
  exit 1
}
command -v dpkg-shlibdeps >/dev/null || {
  printf '%s\n' "dpkg-dev is required." >&2
  exit 1
}

arch="$(dpkg --print-architecture)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg="$stage/pkg"
mkdir -p "$pkg/opt/ros" "$pkg/DEBIAN" "$pkg/usr/share/doc/xgc2-ros-noetic"
cp -a "$PREFIX" "$pkg/opt/ros/noetic"

mkdir -p "$pkg/opt/ros/noetic/etc/catkin/profile.d"
cat > "$pkg/opt/ros/noetic/etc/catkin/profile.d/99-xgc2-geographiclib.sh" << 'EOF'
# Datasets are installed under this prefix. setup.bash sources this file.
if [ -d /opt/ros/noetic/share/GeographicLib/geoids ]; then
  export GEOGRAPHICLIB_DATA=/opt/ros/noetic/share/GeographicLib
fi
EOF

cat > "$pkg/usr/share/doc/xgc2-ros-noetic/README" << 'EOF'
ROS 1 Noetic for Ubuntu 24.04.

On Ubuntu 20.04 the upstream metapackage is ros-noetic-desktop-full.
Ubuntu 24.04 does not publish that package. This package installs the
XGC Noetic build into /opt/ros/noetic. Gazebo Classic is not included.

Load it in a shell when needed:

  source /opt/ros/noetic/setup.bash

Do not add that line to a shell startup file.
EOF

python3 - "$ROOT/apt-host.txt" "$pkg" "$version" "$arch" "$stage" << 'PY'
import pathlib, subprocess, sys
apt_host, pkg, version, arch, stage = sys.argv[1:]
pkg = pathlib.Path(pkg)
stage = pathlib.Path(stage)
deny = {
    "build-essential", "cmake", "git", "curl", "wget", "ca-certificates",
    "lsb-release", "pkg-config", "python3-dev", "python3-venv", "python3-pip",
    "python3-setuptools", "python3-wheel", "python3-packaging", "python3-nose",
    "python3-pytest", "vcstool", "geographiclib-tools", "google-mock",
    "graphviz", "qt5-qmake", "qtbase5-dev", "pyqt5-dev", "sbcl",
}
names = []
for raw in pathlib.Path(apt_host).read_text().splitlines():
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    name = line.split()[0]
    if name in deny or "-dev" in name:
        continue
    names.append(name)
names.append("python3")

libs = []
for path in (pkg / "opt/ros/noetic").rglob("*"):
    if not path.is_file() or ".so" not in path.name:
        continue
    if path.read_bytes()[:4] == b"\x7fELF":
        libs.append(str(path))
shlibs = []
if libs:
    debdir = stage / "debian"
    debdir.mkdir()
    (debdir / "control").write_text(
        "Source: xgc2-ros-noetic\n\nPackage: xgc2-ros-noetic\nArchitecture: any\nDescription: placeholder\n scan\n")
    proc = subprocess.run(
        ["dpkg-shlibdeps", "-O", f"-l{pkg / 'opt/ros/noetic/lib'}",
         "--ignore-missing-info", *libs],
        check=False, text=True, capture_output=True, cwd=stage)
    (stage / "shlibdeps.err").write_text(proc.stderr)
    text = proc.stdout.strip()
    (stage / "shlibdeps.out").write_text(text + "\n")
    marker = "shlibs:Depends="
    if marker not in text:
        sys.stderr.write(proc.stderr)
        sys.stderr.write("dpkg-shlibdeps did not report shared library dependencies.\n")
        sys.exit(1)
    shlibs = [item.strip() for item in text.split(marker, 1)[1].split(",") if item.strip()]

seen = set()
depends = []
for item in [*shlibs, *names]:
    key = item.split("(", 1)[0].strip()
    if key == "xgc2-ros-noetic" or key in seen:
        continue
    seen.add(key)
    depends.append(item)

installed = subprocess.check_output(["du", "-sk", str(pkg / "opt"), str(pkg / "usr")], text=True)
size = sum(int(line.split()[0]) for line in installed.splitlines())
control = f"""Package: xgc2-ros-noetic
Version: {version}
Architecture: {arch}
Maintainer: XGC Team <867768510@qq.com>
Section: science
Priority: optional
Installed-Size: {size}
Depends: {", ".join(depends)}
Description: ROS 1 Noetic for Ubuntu 24.04
 Ubuntu 20.04 ships this role as ros-noetic-desktop-full. Ubuntu 24.04 does not.
 This package installs the XGC Noetic build into /opt/ros/noetic.
 Gazebo Classic is not included, because Ubuntu 24.04 does not ship Gazebo 11.
 Source and the build scripts stay in https://github.com/XGC-Team/xgc2-ros
"""
(pkg / "DEBIAN/control").write_text(control)
PY

out="$ROOT/dist/xgc2-ros-noetic_${version}_${arch}.deb"
mkdir -p "$ROOT/dist"
dpkg-deb --root-owner-group --build "$pkg" "$out"
printf '%s\n' "Wrote ${out}"
