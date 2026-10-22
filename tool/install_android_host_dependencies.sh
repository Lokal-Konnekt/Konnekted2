#!/usr/bin/env bash
# GitHub's Azure apt mirror can trickle downloads for tens of minutes.
# Use isolated official Ubuntu sources, and bound downloads before touching dpkg.
set -euo pipefail
source /etc/os-release
: "${VERSION_CODENAME:?Expected an Ubuntu runner}"
[[ "$ID" == ubuntu ]] || { echo 'Expected an Ubuntu runner' >&2; exit 1; }
apt_sources=$(mktemp --suffix=.list)
trap 'rm -f "$apt_sources"' EXIT
chmod 644 "$apt_sources"
cat > "$apt_sources" <<SOURCES
deb https://archive.ubuntu.com/ubuntu $VERSION_CODENAME main universe restricted multiverse
deb https://archive.ubuntu.com/ubuntu $VERSION_CODENAME-updates main universe restricted multiverse
deb https://security.ubuntu.com/ubuntu $VERSION_CODENAME-security main universe restricted multiverse
SOURCES
apt_options=(
  -o "Dir::Etc::sourcelist=$apt_sources"
  -o 'Dir::Etc::sourceparts=-'
  -o 'Acquire::Retries=1'
  -o 'Acquire::http::Timeout=20'
  -o 'Acquire::https::Timeout=20'
  -o 'Acquire::Languages=none'
)
packages=(libclang-dev clang cmake ninja-build pkg-config libasound2-dev
          libudev-dev libusb-1.0-0-dev autoconf automake libtool)
# Timeouts only surround index/archive downloads, never dpkg unpack/configure.
sudo timeout --kill-after=15s 120s apt-get "${apt_options[@]}" update --error-on=any
if ! sudo timeout --kill-after=15s 240s apt-get "${apt_options[@]}" install \
    --download-only --no-install-recommends -y "${packages[@]}"; then
  echo '::error::Host dependency download failed or exceeded four minutes; no package installation was started.'
  exit 1
fi
sudo env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install \
  --no-download --no-install-recommends -y "${packages[@]}"
