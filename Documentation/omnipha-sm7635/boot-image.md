# Mainline USB-SSH Boot Image Packaging and Test Plan for Qualcomm SM7635 / Milos

Host-side build instructions, bootloader packaging evidence, initramfs design,
unpack-and-compare verification, and temporary-boot test plan for the
Nothing Phone (3a) Pro (A059P, `asteroids`, Qualcomm SM7635 / Milos platform).

This document covers **host preparation, packaging, and verification only**.
It does **not** claim on-device USB enumeration, working SSH, or a tested device boot.
No device flashing, temporary booting, or rebooting was performed.
Physical execution is reserved for the human operator under explicit authorization.

- **Issue:** omnipha/linux-qualcomm-sm7635#2
- **Predecessor:** omnipha/linux-qualcomm-sm7635#1 ([usb-device-mode.md](usb-device-mode.md))
- **Ports Coordination:** [omnipha/ports#6](https://github.com/omnipha/ports/issues/6) ("First Omnipha boot and USB SSH")
- **Vendor Reference:** [omnipha/linux-sm7635](https://github.com/omnipha/linux-sm7635) (`docs/boot-image.md`)

---

## 1. Bootloader Packaging Evidence and Architecture

### 1.1 Bootloader Environment
The Nothing Phone (3a) Pro (A059P) utilizes Qualcomm's Snapdragon Android Bootloader (ABL)
tailored for Android 14 GKI boot specifications on the SM7635 (Volcano/Milos) SoC.

Measurements from the stock slot-A partition references (`~/phone-second-life-data/mb003/parts/`)
establish the following parameters:

| Partition | Size (bytes) | Header | Geometry & Stock Contents |
|---|---|---|---|
| `boot_a` | 100,663,296 (96 MiB) | Android Boot Header v4 | `kernel_size = 13949926` (gzip), `ramdisk_size = 0`, `signature_size = 0`, page size 4096 (implied) |
| `init_boot_a` | 8,388,608 (8 MiB) | Android Boot Header v4 | `kernel_size = 0`, `ramdisk_size = 2113581` (LZ4 generic Android `/init`), `signature_size = 0` |
| `vendor_boot_a` | 100,663,296 (96 MiB) | Vendor Boot Header v4 | Page size 4096 (0x1000), `kernel_addr = 0x8000`, `ramdisk_addr = 0x1000000`, `dtb_addr = 0x1f00000`, `tags_addr = 0x100`, `dtb_size = 9419891` (20 base DTBs), vendor ramdisk 8,821,389 bytes, bootconfig 175 bytes |
| `dtbo_a` | 25,165,824 (24 MiB) | DTBO Table v0 | 76 overlay entries; entry 65 corresponds to Nothing Phone (3a) Pro (`Qualcomm Technologies, Inc. Volcano QRD Pro`, `qcom,board-id = <0x0b 0>`, `qcom,oem-id = <2>`) |
| `vbmeta_a` | 65,536 (64 KiB) | AVB 1.2 | Salted SHA-256 descriptors chaining `boot`, hashing `init_boot`, `vendor_boot`, and `dtbo` |

### 1.2 DTB Delivery Path Decision and Evidence
In Android Boot Image Header Version 4:
1. **`boot.img` Header v4 lacks a DTB field:**
   Android header version 4 explicitly removed the `--dtb` field from `boot.img`. The DTB payload is
   housed exclusively in `vendor_boot.img`.
2. **ABL DTB Retrieval Chain:**
   Stock ABL loads the DTB blob from `vendor_boot`, matches the hardware board ID against the concatenated
   base DTBs, and applies the board overlay selected from `dtbo` (property `ro.boot.dtbo_idx=65`).
3. **Mainline Device Tree Incompatibility with Stock DTBO:**
   The stock DTB blob and stock DTBO entry 65 are strictly designed for the Qualcomm vendor 6.1 kernel.
   In vendor investigation #10, applying stock DTBO 65 to a custom device tree failed (`FDT_ERR_NOTFOUND`)
   due to 32 missing vendor phandle fixups across 82 sites.
   Mainline Linux utilizes independent device-tree bindings defined in this repository:
   `arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dts` (and `milos.dtsi`).
   Mainline cannot use the stock DTBO overlay.
4. **Delivery Decision:**
   - The mainline device tree (`milos-nothing-asteroids-pro.dtb`) is packaged directly into `vendor_boot.img`
     as the single authoritative device tree.
   - For temporary boot exploration via `fastboot boot`, ABL's behavior on this device is documented:
     on 2026-10-19, `fastboot boot boot.img` was accepted by ABL (`Booting OKAY`), but because ABL reads
     `vendor_boot`, `dtbo`, and `init_boot` from flash, `fastboot boot` alone did not deliver a custom DTB or ramdisk.
     Whether ABL on this device accepts a legacy Header v2 image or reads an embedded ramdisk in a Header v4
     `boot.img` during `fastboot boot` remains **unverified** on hardware.

### 1.3 Assumptions and Verification Status

| Item | Evidence Level | Notes |
|---|---|---|
| Header Version 4 & Page Size 4096 | **Verified** from stock partition dumps | Measured directly from `boot_a`, `init_boot_a`, `vendor_boot_a` |
| Load offsets (0x8000, 0x1000000, 0x1f00000) | **Verified** from stock vendor boot header | Measured from `vendor_boot_a` |
| DTB inside `vendor_boot.img` | **Verified** architectural requirement | Header v4 specification and ABL parsing chain |
| `fastboot boot` ABL acceptance | **Verified** command acceptance only | 2026-10-19 attempt returned `Booting OKAY` |
| `fastboot boot` ramdisk override | **Unverified / Refuted by 2026-10-19 run** | ABL fetched stock `init_boot` from flash rather than `boot.img` ramdisk |
| `fastboot boot` Header v2 acceptance | **Unverified / Untested** | No physical test exists for Header v2 on this bootloader |
| USB gadget physical enumeration | **Unverified / Untested** on Mainline | Host preparation and built-in drivers completed; physical boot pending |

---

## 2. Initramfs Architecture and Security Hygiene

The initramfs is assembled as a minimal, standalone root filesystem packaged as an unprivileged,
reproducible newc CPIO archive compressed with `gzip -n -9`.

### 2.1 Component Structure
- **`/init` (`initramfs/init`):**
  POSIX shell script executing under Busybox.
  - Mounts `/proc`, `/sys`, `/dev` (`devtmpfs`), `/sys/kernel/config` (`configfs`), `/dev/pts`.
  - Creates character device nodes (`/dev/console` c 5:1, `/dev/kmsg` c 1:11, `/dev/null` c 1:3, `/dev/zero` c 1:5, `/dev/ptmx` c 5:2).
  - Background 150-second watchdog timer: invokes `/bin/restart2 bootloader` (or `reboot -f`) if `/run/keep` is not touched.
  - Reads DTB model from `/proc/device-tree/model` and kernel release from `uname -r`, logging the banner to `/dev/kmsg` and `/etc/motd`.
  - Configures USB gadget via ConfigFS under `/sys/kernel/config/usb_gadget/g1`.
  - Dynamically detects registered UDC (`a600000.usb`) and writes to `UDC` to assert VBUS override.
  - Configures static IP networking (`192.168.10.2/24` on `usb0`, `192.168.11.2/24` on `usb1`).
  - Launches static Dropbear SSH daemon bound to `192.168.10.2:22`.
  - Spawns interactive fallback shell on console (`setsid cttyhack /bin/sh`).
- **`/bin/busybox`:**
  Static ARM64 binary extracted from `busybox-static_1.37.0-7ubuntu1_arm64.deb` (pinned SHA-256 `fcf50794...`).
- **`/bin/dropbear`:**
  Static ARM64 Dropbear SSH daemon compiled from source `dropbear-2026.94.tar.bz2` (pinned SHA-256 `e098034a...`).
  Compiled with:
  - `DROPBEAR_SVR_PASSWORD_AUTH = 0` (password authentication disabled)
  - `DROPBEAR_SVR_PAM_AUTH = 0` (PAM authentication disabled)
  - `DROPBEAR_SVR_LOCALTCPFWD = 0` / `DROPBEAR_SVR_REMOTETCPFWD = 0`
  - Strict public-key-only authentication.
- **`/bin/restart2` (`initramfs/restart2.c`):**
  Minimal static ARM64 executable invoking `reboot(LINUX_REBOOT_CMD_RESTART2, "bootloader")` via direct Linux syscalls.
- **`/root/.ssh/authorized_keys`:**
  Contains strictly one validated `ssh-ed25519` host public key (injected from `$PUBKEY` or `~/.ssh/id_ed25519.pub`, mode 0600).

### 2.2 Strict Security Hygiene
- **No private keys:** No private host or identity keys are packaged.
- **No firmware blobs:** No proprietary modem, ADSP, or WLAN blobs (`.mbn`, `.bin`, `.fw`) exist in the repository or image.
- **No credentials or secrets:** Password auth is hard-disabled at compile time; only public key auth is permitted.
- **Reproducibility:** All files in the CPIO archive have `uid=0`, `gid=0`, and `mtime=0` (epoch 0).

---

## 3. Host Build and Packaging Instructions

### 3.1 Host Environment Prerequisites
Install required host build and packaging tools:
```sh
sudo apt-get install -y mkbootimg python3 cpio gzip sha256sum dpkg-deb curl file fakeroot dtc tar make gcc-aarch64-linux-gnu
```

### 3.2 Build and Packaging Sequence
From a clean checkout on branch `omnipha`:

```sh
# 1. Resolve configuration and compile kernel Image + DTBs
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig omnipha_usb_gadget.config
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make -j$(nproc) O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    Image qcom/milos-nothing-asteroids.dtb qcom/milos-nothing-asteroids-pro.dtb \
    qcom/milos-fairphone-fp6.dtb

# 2. Package boot images and initramfs
scripts/build-bootimg.sh

# 3. Execute unpack-and-compare verification
scripts/verify-bootimg.sh
```

### 3.3 Verified Artifacts and Checksums

Outputs are placed in `$WORK/out-mainline` (default: `~/sm7635-build/out-mainline`):

| Artifact | Size (bytes) | SHA-256 Checksum | Description |
|---|---|---|---|
| `boot.img` | 15,216,640 | `fcc6b961f2c684544c12300aa2bfbd5d827db1190e813d8ea136d4fe836749d5` | Header v4, mainline `Image.gz`, empty ramdisk |
| `init_boot.img` | 1,679,360 | `85be2f41b14b05edb40b0d3e49b6ac9d3fb8f5d28ce8abaade8920135ad914ed` | Header v4, empty kernel, generic initramfs |
| `vendor_boot.img` | 1,761,280 | `4cf5fd279b94e67364e73ebea4b2971d664e5f42e90cc20fbf21ce1baaa98d29` | Header v4, Pro DTB with framebuffer, vendor ramdisk, bootconfig |
| `boot-standalone.img` | 16,891,904 | `fab1314a36160ea39c0ac950e171042464440813cfb5316da3c81fd181e75d6f` | Header v4, `Image.gz` + embedded initramfs (`console=tty0`) |
| `dtb.img` | 69,777 | `4b45b5f6c8a4fd5ea151d73c595b7416a3d33dca9f6cab3656d50066edbb9a79` | Mainline `milos-nothing-asteroids-pro.dtb` (with simple-framebuffer) |
| `Image` (raw) | 43,158,016 | `44e1cc158387317da25075c68c0e684cc0144d83041a0e6124221577943cb7c0` | Raw uncompressed mainline kernel Image |
| `Image.gz` | 15,210,129 | `f53d6409f49f84d8658e419772bf0e3ff3902a778c381a32fc2655bbc578d0a7` | Mainline kernel gzip payload |
| `initramfs.cpio.gz` | 1,674,591 | `2322283eac2d2fdb643fd2bfd8d8cf17963eb1f616be1db87b9d9467705b7ab4` | Reproducible CPIO initramfs archive |

Checksums are recorded in `$WORK/out-mainline/bootimg-sha256.txt` and verified with `sha256sum -c`.

---

## 4. Test Plan and Preconditions for Physical Boot

> [!IMPORTANT]
> **Operator Authorization Required:**
> Physical boot or device connection must be executed exclusively by the human operator/coordinator.
> A coding agent must never execute device commands (`fastboot`, `adb`, reboot).

### 4.1 Preconditions and Preflight Checks
Before connecting the device or running any physical command:
1. **Device Identification:**
   Verify the physical unit serial number and board ID match private test records (`unit mb003`, A059P).
2. **Backup Verification:**
   Verify that verified slot-A and slot-B stock partition backups exist on the host:
   - `boot_a.img` (`197aff11...`)
   - `init_boot_a.img` (`baa33fd4...`)
   - `vendor_boot_a.img` (`23725940...`)
   - `dtbo_a.img` (`759813db...`)
   - `vbmeta_a.img` (`cc1926d2...`)
3. **Recovery Path Verification:**
   Confirm that fastboot access and key combinations (Power + Vol Down) reliably enter bootloader mode.
   No persistent partition write is authorized under this issue.

### 4.2 Temporary Boot Procedure (`fastboot boot`)
The first physical attempt must use **temporary boot** only:

```sh
# 1. Confirm device is in fastboot mode and check active slot
fastboot devices
fastboot getvar current-slot

# 2. Boot standalone test image in RAM (leaves flash partitions untouched)
fastboot boot ~/sm7635-build/out-mainline/boot-standalone.img
```

### 4.3 Success Criteria
On successful boot:
1. **On-Screen Display Console (`tty0` via SimpleDRM):**
   - The bootloader splash remains lit during kernel handover without screen flicker or blackout.
   - High-DPI Terminus 16x32 font initializes on the 1080x2392 panel (`fbcon=font:TER16x32`).
   - Kernel boot log messages scroll legibly on `/dev/tty0`.
   - Initramfs prints the identity banner to the display:
     ```
     ======================================================================
      Omnipha Mainline Linux for Qualcomm SM7635 (Milos)
      Device:  Nothing Phone (3a) Pro
      Kernel:  7.3.0-...
      Address: 172.16.42.2 / 192.168.10.2 (USB CDC ECM/NCM)
      Access:  Key-only Dropbear SSH (root)
      Console: /dev/tty0 (bootloader framebuffer)
     ======================================================================
     ```
   - An interactive fallback root shell prompt (`# `) appears on the phone screen.
2. **USB Enumeration:**
   Host detects USB gadget within 15–30 seconds:
   `lsusb -d 1d6b:0104` returns `ID 1d6b:0104 Linux Foundation Multifunction Composite Gadget`.
3. **Network Interface:**
   Host network manager or kernel detects network interface (`usb0` or `enp...`).
   Host configures `172.16.42.1/24` (or `192.168.10.1/24`):
   ```sh
   sudo ip addr add 172.16.42.1/24 dev <host-interface>
   sudo ip link set dev <host-interface> up
   ping -c 3 172.16.42.2
   ```
4. **SSH Access:**
   ```sh
   ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@172.16.42.2
   ```
   - No password prompt is requested.
   - Motd banner confirms device identity (`Nothing Phone (3a) Pro`) and kernel release.
   - `uname -r` confirms the mainline kernel release.
   - Command `touch /run/keep` cancels the 150-second watchdog.

### 4.4 On-Screen Display Scope and Boundaries

#### 4.4.1 What the On-Screen Result Proves
- **Intact scanout memory:** Validates that the bootloader continuous splash region at physical
  address `0xe3940000` (43 MiB) remains preserved and undisturbed by kernel memory initialization.
- **Reserved-memory enforcement:** Confirms that the `cont_splash_mem` node in `reserved-memory`
  successfully prevents page allocations from overwriting scanout memory.
- **Driver binding and console pipeline:** Confirms `CONFIG_DRM_SIMPLEDRM`, `CONFIG_DRM_FBDEV_EMULATION`,
  `CONFIG_FRAMEBUFFER_CONSOLE`, and `CONFIG_FONT_TER16x32` operate cleanly on 64-bit ARM.
- **Fail-safe diagnostic visibility:** If USB enumeration fails on the host, the phone display
  provides immediate visual feedback showing deferred probe status, kernel errors, and init execution.

#### 4.4.2 What the On-Screen Result Does NOT Prove (Explicit Out-of-Scope List)
- **A lit screen is NOT a functional display stack:** The scanout buffer is merely scanning out memory
  configured previously by the Qualcomm ABL bootloader.
- **No native DSI controller:** The Qualcomm DPU / MDSS display controller driver (`qcom,milos-mdss` /
  `qcom,milos-dpu`) is disabled (`status = "disabled"` in DT); no native KMS modesetting occurs.
- **No native panel driver:** Neither the BOE `rm69220` nor Focaltech `ft8726` panel driver is probed.
- **No brightness or backlight control:** Backlight PWM / DCS DBV brightness control remains inactive;
  the panel operates solely at the brightness set by the bootloader.
- **No touchscreen input:** The Focaltech `focaltech,fts_ts` SPI touchscreen driver is out of scope.
- **No power management or refresh switching:** Display runtime PM, panel sleep/wakeup, and dynamic
  framerate switching (60 Hz / 120 Hz) remain out of scope.

### 4.5 Rollback Expectation
- **For Candidate 2 (`fastboot boot boot-standalone.img`):**
  Loads the image into RAM only. All on-flash partitions remain completely unaltered.
  Powering off or issuing a hard reset (holding Power button for 10 seconds) immediately returns
  the phone to the stock Android system on slot A. No user data, recovery, or bootloader partition is touched.
- **For Candidate 1 (flashed to Slot B carrier):**
  Flashing targets `boot_b`, `init_boot_b`, and `vendor_boot_b`. Active slot A remains 100% untouched stock Android.
  Returning to stock Android requires only `fastboot set_active a`. See detailed, verified rollback steps
  and checksums in [best-shot-review.md](best-shot-review.md).

### 4.6 Abort Conditions and Failure Paths
The operator must abort the test immediately if any of the following occur:
1. **Fastboot command failure:**
   `fastboot boot` returns error or rejects the header.
   *Action:* Disconnect USB, do not flash partitions.
2. **Display corruption or hang without USB:**
   Screen goes blank or artifacts appear and neither `1d6b:0104` nor watchdog reset occurs within 180s.
   *Action:* Hard reset by holding Power button for 10 seconds.
3. **No USB enumeration within 45 seconds:**
   Device screen remains blank, no `1d6b:0104` appears in host `dmesg` or `lsusb`.
   *Action:* Check host `dmesg` for USB resets; power off device to return to stock Android.
4. **USB enumeration without network:**
   Device appears in `lsusb` but network interface fails to bind or DHCP/static IP fails.
   *Action:* Capture `lsusb -v`, check for endpoint errors.
5. **SSH refused:**
   Network is up, port 22 is closed or drops packets.
   *Action:* Check host `nmap -p 22 192.168.10.2` and host route table.
6. **Watchdog expiry:**
   If the device reboots to fastboot/bootloader after 150 seconds, the watchdog acted as designed.

---

## 5. Physical Test Results

**Status: UNTESTED / UNVERIFIED**

No physical boot, flashing, or hardware test was conducted.
Host build and unpack-and-compare verification are 100% complete.
Device acceptance testing will be recorded under [omnipha/ports#6](https://github.com/omnipha/ports/issues/6).
