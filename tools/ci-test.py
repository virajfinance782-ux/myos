#!/usr/bin/env python3
"""Boots the ISO in QEMU without a display, drives it with key presses and
saves screenshots.   Usage: ci-test.py <iso> <bios|uefi> <output-dir>"""
import os, shutil, socket, subprocess, sys, time

iso, mode, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
kvm = os.access("/dev/kvm", os.R_OK | os.W_OK)
slow = 1 if kvm else 6
sock = f"/tmp/mon-{mode}.sock"

cmd = ["qemu-system-x86_64", "-m", "4096", "-smp", "2", "-cdrom", iso, "-boot", "d",
       "-display", "none", "-vga", "std", "-nic", "user,model=virtio-net-pci",
       "-monitor", f"unix:{sock},server,nowait"]
cmd += ["-accel", "kvm", "-cpu", "host"] if kvm else ["-accel", "tcg", "-cpu", "max"]
if mode == "uefi":
    shutil.copy("/usr/share/OVMF/OVMF_VARS_4M.fd", "/tmp/vars.fd")
    cmd += ["-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd",
            "-drive", "if=pflash,format=raw,file=/tmp/vars.fd"]
print("KVM:", kvm, "|", " ".join(cmd), flush=True)
vm = subprocess.Popen(cmd)
time.sleep(3)

def mon(line):
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock)
    s.settimeout(5)
    try:
        s.recv(4096)
    except socket.timeout:
        pass
    s.sendall((line + "\n").encode())
    time.sleep(0.4)
    try:
        s.recv(4096)
    except socket.timeout:
        pass
    s.close()

n = 0
def shot(name):
    global n
    n += 1
    path = os.path.abspath(os.path.join(out, f"{mode}-{n}-{name}.ppm"))
    mon(f"screendump {path}")
    print("screenshot", path, flush=True)

KEYS = {" ": "spc", "-": "minus", ".": "dot", "/": "slash", ":": "shift-semicolon"}
def type_text(text):
    for ch in text:
        key = KEYS.get(ch) or (f"shift-{ch.lower()}" if ch.isupper() else ch)
        mon(f"sendkey {key}")

def run(command):
    mon("sendkey alt-f2")
    time.sleep(4 * slow)
    type_text(command)
    time.sleep(1)
    mon("sendkey ret")

time.sleep(8 * slow)
shot("boot-8s")
mon("sendkey ret")          # BIOS menu is up by now
time.sleep(22 * slow)
shot("boot-30s")
time.sleep(15 * slow)
shot("boot-45s")
time.sleep(15 * slow)
shot("boot-60s")
mon("sendkey ret")          # UEFI menu, if it is still waiting
time.sleep(100 * slow)
shot("desktop")
run("chromium https://example.com")
time.sleep(45 * slow)
shot("chromium-https")
if True:
    run("xfce4-terminal -H -x nmcli device")
    time.sleep(10 * slow)
    shot("network-status")
    run("gnome-software")
    time.sleep(50 * slow)
    shot("app-store")
mon("quit")
try:
    vm.wait(timeout=20)
except subprocess.TimeoutExpired:
    vm.kill()
