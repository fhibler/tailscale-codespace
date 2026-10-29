#!/usr/bin/env bash
# Copyright (c) 2022 Tailscale Inc & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

set -xeuo pipefail

export DEBIAN_FRONTEND=noninteractive

platform=$(uname -m)
if [ "$platform" = "x86_64" ]; then
    tailscale_url="https://pkgs.tailscale.com/stable/tailscale_${VERSION}_amd64.tgz"
elif [ "$platform" = "aarch64" ] || [ "$platform" = "arm64" ]; then
    tailscale_url="https://pkgs.tailscale.com/stable/tailscale_${VERSION}_arm64.tgz"
else
    echo "Unsupported platform: $platform"
    exit 1
fi

install_packages() {
  if type apt-get > /dev/null 2>/dev/null; then
    apt-get update
    # install recommends left on so we get ca-certificates.
    apt-get -y install "$@"
  elif type microdnf > /dev/null 2>/dev/null; then
    microdnf makecache
    microdnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0 "$@"
  elif type dnf > /dev/null 2>/dev/null; then
    # check-update exits 100 when updates are available, which is not an error.
    dnf check-update || [ $? -eq 100 ]
    dnf -y install --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0 "$@"
  elif type yum > /dev/null 2>/dev/null; then
    yum -y install --noplugins --setopt=install_weak_deps=0 "$@"
  elif type apk > /dev/null 2>/dev/null; then
    apk add "$@"
  else
    >&2 echo "Unknown platform, can not automate install of: $*"
    return 1
  fi
}

CURL_INSTALL_ATTEMPTED=""
install_curl() {
  CURL_INSTALL_ATTEMPTED=1
  install_packages curl
}

download() {
  if command -v curl &> /dev/null; then
    curl -fsSL "$@"
  elif command -v wget &> /dev/null; then
    wget -qO - "$@"
  else
    if [[ -z "$CURL_INSTALL_ATTEMPTED" ]]; then
      install_curl >&2
      download "$@"
    else
      echo "Must install curl or wget to download $1" >&2
      return 1
    fi
  fi
}

script_dir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
scratch_dir="/tmp/tailscale"
mkdir -p "$scratch_dir"
trap 'rm -rf "$scratch_dir" /var/lib/apt/lists/*' EXIT

download "$tailscale_url" | tar -xzf - --strip-components=1 -C "$scratch_dir"
install -D -m 755 "$scratch_dir/tailscale" /usr/local/bin/tailscale
install -D -m 755 "$scratch_dir/tailscaled" /usr/local/sbin/tailscaled
install -D -m 755 "$script_dir/tailscaled-entrypoint.sh" /usr/local/sbin/tailscaled-entrypoint
install -D -m 755 "$script_dir/tailscaled-devcontainer-start.sh" /usr/local/sbin/tailscaled-devcontainer-start
install -D -m 644 "$script_dir/tailscale-guard.zsh" /usr/local/share/tailscale/tailscale-guard.zsh

# Source the TS_ENFORCE guard from every system zshrc that exists: Debian and
# Alpine use /etc/zsh/zshrc, RHEL-likes /etc/zshrc. Creating one would clash
# with a zsh package installed later, so a zsh added after this feature (other
# than by common-utils, see installsAfter) does not get the guard.
guard_source='[[ -r /usr/local/share/tailscale/tailscale-guard.zsh ]] && source /usr/local/share/tailscale/tailscale-guard.zsh'
guard_hooked=""
for zshrc in /etc/zsh/zshrc /etc/zshrc; do
  [[ -f "$zshrc" ]] || continue
  grep -qxF "$guard_source" "$zshrc" || printf '\n# tailscale devcontainer feature: TS_ENFORCE guard\n%s\n' "$guard_source" >> "$zshrc"
  guard_hooked=1
done
if [[ -z "$guard_hooked" ]]; then
  >&2 echo "WARNING: no system zshrc found, the TS_ENFORCE guard is not active."
fi

mkdir -p /var/lib/tailscale /var/run/tailscale /var/log
touch /var/log/tailscaled.log

if ! command -v iptables >& /dev/null; then
  if command -v apt-get >& /dev/null; then
    apt-get update
    apt-get install -y --no-install-recommends iptables
  else
    >&2 echo "WARNING: iptables not installed. tailscaled might fail."
  fi
fi

# The TS_ENFORCE guard parses `tailscale status --json` with jq.
if ! command -v jq >& /dev/null; then
  install_packages jq || >&2 echo "WARNING: jq not installed. The TS_ENFORCE guard will report every shell as unsecure."
fi
