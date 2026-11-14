#!/usr/bin/env bash
# Adds a persistence partition to a USB stick that already has MyOS written
# to it with dd / Etcher / Rufus "DD image mode".
#
#   sudo tools/add-persistence.sh /dev/sdX
#
# The rest of the stick becomes an ext4 partition labelled "persistence".
# The MyOS system itself is not touched.
set -euo pipefail

dev="${1:-}"
if [ -z "$dev" ] || [ ! -b "$dev" ]; then
	echo "Usage: sudo $0 /dev/sdX    (the whole USB stick, not a partition)" >&2
	lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINTS
	exit 2
fi
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }

if [ "$(lsblk -dno TYPE "$dev")" != "disk" ]; then
	echo "$dev is not a whole disk." >&2; exit 1
fi
if [ "$(lsblk -dno TRAN "$dev")" != "usb" ]; then
	echo "REFUSING: $dev is not a USB device." >&2; exit 1
fi
sigs="$(blkid "$dev" "$dev"?* 2>/dev/null || true)"
if ! grep -q 'TYPE="iso9660"' <<<"$sigs"; then
	echo "REFUSING: $dev does not look like a stick with a live ISO on it." >&2; exit 1
fi
if grep -q 'LABEL="persistence"' <<<"$sigs"; then
	echo "$dev already has a persistence partition."; exit 0
fi

lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,LABEL "$dev"
read -r -p "Add a persistence partition in the free space of $dev? [type YES] " ans
[ "$ans" = "YES" ] || { echo "Cancelled."; exit 1; }

for p in "$dev"?*; do umount "$p" 2>/dev/null || true; done

before="$(lsblk -lnpo NAME "$dev" | sort)"
# New primary partition, next free number, filling the remaining space.
printf 'n\np\n\n\n\nw\n' | fdisk "$dev" || true
partprobe "$dev" 2>/dev/null || true
udevadm settle 2>/dev/null || true
sleep 2
after="$(lsblk -lnpo NAME "$dev" | sort)"
part="$(comm -13 <(echo "$before") <(echo "$after") | tail -n1)"
if [ -z "$part" ]; then
	echo "ERROR: no new partition appeared. Unplug and re-plug the stick, then check with lsblk." >&2
	exit 1
fi

echo "Formatting $part ..."
mkfs.ext4 -F -L persistence "$part"
mnt="$(mktemp -d)"
mount "$part" "$mnt"
echo "/ union" > "$mnt/persistence.conf"
umount "$mnt"; rmdir "$mnt"
sync
echo "Done. Boot MyOS from this stick; files and settings are now kept across reboots."
