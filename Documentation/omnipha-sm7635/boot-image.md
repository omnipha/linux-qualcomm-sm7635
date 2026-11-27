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
| `boot.img` | 14,938,112 | `07fc402a9d1e41d12299f30beec34269a7ff9d1bc6349d0f9c1ff239a56ef9a7` | Header v4, mainline `Image.gz`, empty ramdisk |
| `init_boot.img` | 1,679,360 | `97ec0cb40ab25ac1988fed38fb47ba46b48a7d86fd6e8c45e00680a6b89b86fe` | Header v4, empty kernel, generic initramfs |
| `vendor_boot.img` | 1,757,184 | `d2fd4c915c8a4b85b390cd9e576e01a763beec74d164d491f79eb82a336e003e` | Header v4, DTB, vendor ramdisk, bootconfig |
| `boot-standalone.img` | 16,613,376 | `a6362341663ddbbc08d44ae9d1710beea70b66f336cfa9a5d54e4b960d6883b1` | Header v4, `Image.gz` + embedded initramfs |
| `dtb.img` | 69,470 | `25ee4f8dd5789bc679d009712bba0e14d06ac1b8df65131e8d35219b24663228` | Mainline `milos-nothing-asteroids-pro.dtb` |
| `Image.gz` | 14,931,336 | `56a1b6f45868d3c81a80fa17bf169a5ad805dfcd2dc67d4c2a90826bb7a2462c` | Mainline kernel gzip payload |
| `initramfs.cpio.gz` | 1,674,441 | `bbedbb58b2275b102233c560057107bcb56a00f00ed9bdbe8e5adfa61084b5a4` | Reproducible CPIO initramfs archive |

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
1. **USB Enumeration:**
   Host detects USB gadget within 15–30 seconds:
   `lsusb -d 1d6b:0104` returns `ID 1d6b:0104 Linux Foundation Multifunction Composite Gadget`.
2. **Network Interface:**
   Host network manager or kernel detects network interface (`usb0` or `enp...`).
   Host configures `192.168.10.1/24`:
   ```sh
   sudo ip addr add 192.168.10.1/24 dev <host-interface>
   sudo ip link set dev <host-interface> up
   ping -c 3 192.168.10.2
   ```
3. **SSH Access:**
   ```sh
   ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.10.2
   ```
   - No password prompt is requested.
   - Banner displays:
     ```
     Omnipha Mainline Linux for Qualcomm SM7635 (Milos)
     Device:  Nothing Phone (3a) Pro
     Kernel:  7.3.0-...
     ```
   - `uname -r` confirms the mainline kernel release.
   - Command `touch /run/keep` cancels the 150-second watchdog.

### 4.4 Rollback Expectation
Because `fastboot boot` loads the image into RAM only:
- All on-flash partitions remain completely unaltered.
- Powering off or issuing a hard reset (holding Power button for 10 seconds) immediately returns
  the phone to the stock Android system on slot A.
- No user data, recovery, or bootloader partition is touched.

### 4.5 Abort Conditions and Failure Paths
The operator must abort the test immediately if any of the following occur:
1. **Fastboot command failure:**
   `fastboot boot` returns error or rejects the header.
   *Action:* Disconnect USB, do not flash partitions.
2. **No USB enumeration within 45 seconds:**
   Device screen remains blank, no `1d6b:0104` appears in host `dmesg` or `lsusb`.
   *Action:* Check host `dmesg` for USB resets; power off device to return to stock Android.
3. **USB enumeration without network:**
   Device appears in `lsusb` but network interface fails to bind or DHCP/static IP fails.
   *Action:* Capture `lsusb -v`, check for endpoint errors.
4. **SSH refused:**
   Network is up, port 22 is closed or drops packets.
   *Action:* Check host `nmap -p 22 192.168.10.2` and host route table.
5. **Watchdog expiry:**
   If the device reboots to fastboot/bootloader after 150 seconds, the watchdog acted as designed.

---

## 5. Physical Test Results

**Status: UNTESTED / UNVERIFIED**

No physical boot, flashing, or hardware test was conducted.
Host build and unpack-and-compare verification are 100% complete.
Device acceptance testing will be recorded under [omnipha/ports#6](https://github.com/omnipha/ports/issues/6).
