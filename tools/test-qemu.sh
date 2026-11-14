#!/usr/bin/env bash
# Boots the built ISO in QEMU so you can check it before writing a USB stick.
#
#   tools/test-qemu.sh bios  [MyOS-....iso]
#   tools/test-qemu.sh uefi  [MyOS-....iso]
#
# Needs: sudo apt install qemu-system-x86 ovmf
set -euo pipefail
mode="${1:-bios}"
iso="${2:-$(ls -1t "$(dirname "$0")"/../MyOS-*-amd64.iso 2>/dev/null | head -n1 || true)}"
[ -f "$iso" ] || { echo "ISO not found. Pass its path as the second argument." >&2; exit 1; }

accel=(-accel tcg)
[ -w /dev/kvm ] && accel=(-enable-kvm -cpu host)
args=(-m 4096 -smp 2 "${accel[@]}" -cdrom "$iso" -boot d
      -vga virtio -device intel-hda -device hda-duplex
      -nic user,model=virtio-net-pci)

case "$mode" in
	bios) exec qemu-system-x86_64 "${args[@]}" ;;
	uefi)
		fw=""
		for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
			[ -f "$f" ] && { fw="$f"; break; }
		done
		[ -n "$fw" ] || { echo "OVMF firmware not found (sudo apt install ovmf)." >&2; exit 1; }
		exec qemu-system-x86_64 "${args[@]}" -drive "if=pflash,format=raw,readonly=on,file=$fw" ;;
	*) echo "Usage: $0 bios|uefi [iso]" >&2; exit 2 ;;
esac
