# MyOS

A live Linux system you write to a USB stick and boot on ordinary 64-bit PCs
(UEFI and legacy BIOS) without installing anything to the computer's disk.

- Base: Debian 13 "trixie" (current stable), built with live-build
- Desktop: XFCE, automatic login as user `live` (password `live`, sudo without password)
- Browser: Chromium (the Debian `chromium` package)
- App store: GNOME Software ("Software" in the menu) - Debian packages plus Flatpak apps from Flathub
- Network: NetworkManager with tray applet, Ethernet by DHCP, Wi-Fi firmware included
- Apps: Thunar, XFCE Terminal, Mousepad, Atril (PDF), Ristretto (images), VLC,
  LibreOffice, Xarchiver, screenshot tool, GParted, curl, wget, git, htop
- Audio (PipeWire), Bluetooth (Blueman), printing (CUPS)
- Reads and writes exFAT, NTFS and FAT drives
- Locale en_IN, keyboard us, timezone Asia/Kolkata, hostname `myos`

> **Status:** this project was written and statically checked, but the ISO has
> **not** been built or booted yet. See "What has and hasn't been tested".

## 1. Get the ISO

### Option A - no Linux PC needed (GitHub builds it)

1. Create a free GitHub account and a new **public** repository.
2. Upload the contents of this folder to it (including the `.github` folder).
3. Open the **Actions** tab, pick **Build MyOS ISO**, press **Run workflow**.
4. After roughly an hour, open the finished run and download **MyOS-iso**
   from its **Artifacts** section. Unzip it to get the `.iso`.

### Option B - on your own Debian or Ubuntu machine

```
sudo ./build.sh
```

That is the whole build. It installs what it needs, builds, and leaves
`MyOS-YYYYMMDD-amd64.iso` plus a `.sha256` file in this folder.

- Needs: internet, about 25 GB free disk, 30-90 minutes.
- Debian 13 or newer: builds directly.
- Ubuntu / older Debian: Ubuntu's own `live-build` is a years-old fork that
  cannot build this, so the script runs the build inside an official
  `debian:trixie` container (it installs Docker if neither Docker nor Podman
  is present).
- `sudo ./build.sh --clean` removes all build output.
- The build stops with an error if the ISO is over 12 GB. The expected size
  is about 3-4 GB (an estimate; not measured).

To change the name, locale, timezone or Debian release, edit `myos.conf`.
To add or remove software, edit the files in `config/package-lists/`.

## 2. Write it to a USB stick (4 GB or bigger; everything on it is erased)

**Linux**

```
lsblk                       # find the stick, e.g. /dev/sdX - check the size!
sudo dd if=MyOS-YYYYMMDD-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**Windows**

- **balenaEtcher:** Flash from file -> select the ISO -> select the stick -> Flash.
- **Rufus:** select the stick and the ISO, press Start. When asked, choose
  **"Write in DD Image mode"** for an exact copy. (ISO mode also works and lets
  you set a "Persistent partition size" slider - see section 4.)

## 3. Boot it

1. Plug in the stick, switch on, and open the boot menu
   (usually F12, F9, F10, Esc or F2 depending on the maker).
2. Choose the USB stick. Pick the first menu entry.
3. The desktop appears with no login prompt.

**Secure Boot:** the image uses Debian's signed shim, GRUB and kernel, so it
should boot with Secure Boot switched on. Two caveats:

- Some newer PCs (Lenovo, Dell, HP "Secured-core") only trust Microsoft's
  Windows key by default. In the firmware setup, enable
  "Allow Microsoft 3rd Party UEFI CA", or turn Secure Boot off.
- If the firmware reports a security violation or "SBAT" error, the PC's
  revocation list is newer than the shim in the image. Rebuild the ISO to pick
  up the current shim, or turn Secure Boot off.

**Wi-Fi:** click the network icon in the top-right tray and choose your network.

## 4. Optional: keep files and settings (persistence)

Without persistence, everything is forgotten at shutdown. The system already
boots with the `persistence` option; it only needs a partition to use.

**From Linux** (after writing the stick with dd or Etcher):

```
sudo tools/add-persistence.sh /dev/sdX
```

This turns the unused rest of the stick into an ext4 partition labelled
`persistence` containing a `persistence.conf` with the line `/ union`.
You can run it from MyOS itself if you boot MyOS from a *different* stick.

By hand, the same thing is:

```
sudo fdisk /dev/sdX          # n, p, Enter, Enter, Enter, w
sudo mkfs.ext4 -L persistence /dev/sdX3     # use the new partition's number
sudo mount /dev/sdX3 /mnt && echo "/ union" | sudo tee /mnt/persistence.conf && sudo umount /mnt
```

**From Windows:** in Rufus, keep ISO mode and move the
**Persistent partition size** slider before pressing Start.

Notes: apps installed from the app store are stored in RAM unless persistence
is set up, so set it up before installing large apps. MyOS uses any volume
labelled `persistence` that contains a `persistence.conf`, on any attached disk.

## 5. Test in a virtual machine (optional)

```
sudo apt install qemu-system-x86 ovmf
tools/test-qemu.sh bios
tools/test-qemu.sh uefi
```

## Project layout

```
build.sh                       one-command build
myos.conf                      name, release, locale, timezone, size limit
auto/config|build|clean        live-build options
config/package-lists/          what gets installed
config/hooks/normal/           build-time setup (locale, branding, Flathub, boot menu)
config/includes.chroot/        files copied into the system (wallpaper, settings)
config/includes.binary/        boot splash images
tools/                         persistence and QEMU helpers
.github/workflows/             cloud build
```

## What has and hasn't been tested

Checked where this was written (a sandbox with no internet and no build tools):

- Shell syntax of every script (`bash -n` / `dash -n`).
- Debian stable confirmed as 13 "trixie" by lookup; live-build in trixie is 1:20250505.
- Looked up in trixie: `network-manager-applet`, `nm-connection-editor`,
  `atril`, `7zip`, `lxpolkit`, `firmware-atheros`, and that
  `policykit-1-gnome` no longer exists (so it is not used).

Not tested - nothing below has been run:

- `lb config` and `lb build` (live-build could not be installed).
- That every package name resolves. The rest of the names are standard but
  were not individually looked up; least certain are `firmware-mediatek`,
  `gnome-software-plugin-flatpak` and `chromium-sandbox`. If one is wrong the
  build stops early with "Unable to locate package NAME" - delete that line
  from `config/package-lists/` and run again.
- Booting in BIOS or UEFI, Secure Boot, auto-login, network, Chromium loading
  a page, the app store, the wallpaper/boot-menu branding, persistence,
  the Docker path of `build.sh`, and the GitHub workflow.
