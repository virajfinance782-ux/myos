#!/usr/bin/env bash
# MyOS - one-command build.   Usage:  sudo ./build.sh
#
# On Debian 13 or newer the ISO is built directly on this machine.
# On Ubuntu or older Debian (whose live-build is too old for this config) the
# same build runs inside an official Debian container via Docker or Podman.
#
#   sudo ./build.sh            build the ISO
#   sudo ./build.sh --clean    remove all build output (keeps the project)
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
# shellcheck disable=SC1091
. ./myos.conf

MODE="auto"
case "${1:-}" in
	--native) MODE="native" ;;
	--clean)  MODE="clean" ;;
	"")       ;;
	*) echo "Usage: sudo ./build.sh [--clean]" >&2; exit 2 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
	echo "Root is required; re-running with sudo..."
	exec sudo -E bash "$0" "$@"
fi

# Uploading through a web UI or unzipping on Windows drops the executable bit.
chmod +x build.sh auto/* config/hooks/normal/* tools/*.sh \
	config/includes.chroot/usr/local/bin/*

say() { printf '\n==> %s\n' "$*"; }

host_is_new_debian() {
	[ -r /etc/os-release ] || return 1
	# shellcheck disable=SC1091
	( . /etc/os-release
	  [ "${ID:-}" = "debian" ] && [ "${VERSION_ID%%.*}" -ge 13 ] 2>/dev/null )
}

clean_native() {
	if command -v lb >/dev/null 2>&1; then lb clean --purge || true; fi
	rm -rf .build cache chroot binary local build.log ./*.iso ./*.sha256 \
		./myos-amd64.* chroot.* binary.* 2>/dev/null || true
	rm -f config/binary config/bootstrap config/chroot config/common config/source
}

build_native() {
	export DEBIAN_FRONTEND=noninteractive
	say "Installing build dependencies"
	apt-get update
	apt-get install -y --no-install-recommends \
		live-build debootstrap debian-archive-keyring xorriso squashfs-tools \
		mtools dosfstools cpio curl ca-certificates

	say "Checking that '${MYOS_SUITE}' is still Debian stable"
	stable="$(curl -fsSL --max-time 20 https://deb.debian.org/debian/dists/stable/Release 2>/dev/null \
		| awk '/^Codename:/{print $2; exit}' || true)"
	if [ -z "$stable" ]; then
		echo "Could not check (no answer from deb.debian.org); continuing with ${MYOS_SUITE}."
	elif [ "$stable" != "$MYOS_SUITE" ]; then
		echo "NOTE: Debian stable is now '${stable}', this project is set to '${MYOS_SUITE}'."
		echo "      Edit MYOS_SUITE in myos.conf to move to the new release."
	else
		echo "OK: ${MYOS_SUITE} is the current stable release."
	fi

	free_gb=$(( $(df -Pk . | awk 'NR==2{print $4}') / 1024 / 1024 ))
	if [ "$free_gb" -lt 25 ]; then
		echo "WARNING: only ${free_gb} GB free here; about 25 GB is recommended."
	fi

	say "Configuring (lb config)"
	lb clean || true
	rm -f config/binary config/bootstrap config/chroot config/common config/source
	lb config

	say "Building the image - this takes 30 to 90 minutes"
	lb build 2>&1 | tee build.log

	iso="$(ls -1 myos-amd64*.iso 2>/dev/null | head -n1 || true)"
	if [ -z "$iso" ]; then
		echo "ERROR: build finished without producing an ISO. See build.log." >&2
		exit 1
	fi
	out="${MYOS_NAME}-$(date +%Y%m%d)-amd64.iso"
	mv -f "$iso" "$out"
	sha256sum "$out" > "$out.sha256"

	bytes=$(stat -c %s "$out")
	max=$(( MYOS_MAX_GB * 1024 * 1024 * 1024 ))
	say "Done"
	echo "ISO:     $(pwd)/$out"
	echo "Size:    $(( bytes / 1024 / 1024 )) MB"
	echo "SHA256:  $(cut -d' ' -f1 "$out.sha256")"
	if [ "$bytes" -gt "$max" ]; then
		echo "ERROR: the ISO is larger than the ${MYOS_MAX_GB} GB limit." >&2
		exit 1
	fi
	# Hand the files back to the user who called sudo.
	if [ -n "${SUDO_UID:-}" ]; then chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$out" "$out.sha256" build.log || true; fi
}

container_tool() {
	if command -v docker >/dev/null 2>&1; then echo docker
	elif command -v podman >/dev/null 2>&1; then echo podman
	else
		say "Installing Docker (needed because this host's live-build is too old)" >&2
		apt-get update >&2
		DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io >&2
		systemctl start docker >&2 2>/dev/null || true
		echo docker
	fi
}

run_in_container() {
	tool="$(container_tool)"
	say "Building inside a debian:${MYOS_SUITE} container using ${tool}"
	"$tool" run --rm --privileged \
		-v "$(pwd)":/work -w /work \
		"debian:${MYOS_SUITE}" bash ./build.sh "$1"
	if [ -n "${SUDO_UID:-}" ]; then
		chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" ./*.iso ./*.sha256 build.log 2>/dev/null || true
	fi
}

case "$MODE" in
	native) build_native ;;
	clean)
		if host_is_new_debian || [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then clean_native
		else rm -rf .build cache chroot binary local build.log ./*.iso ./*.sha256 2>/dev/null || true
		     rm -f config/binary config/bootstrap config/chroot config/common config/source
		fi
		echo "Cleaned." ;;
	auto)
		if host_is_new_debian; then build_native; else run_in_container --native; fi ;;
esac
