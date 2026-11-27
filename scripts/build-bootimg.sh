#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Build and package minimal Mainline USB-SSH boot image for Qualcomm SM7635
# Target: Nothing Phone (3a) Pro (A059P, asteroids)
#
set -euo pipefail

umask 022

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${WORK:-$HOME/sm7635-build}
OUT=${OUT:-$WORK/out-mainline}
KERNEL_OUT=${KERNEL_OUT:-$ROOT/out}

BUSYBOX_DEB=${BUSYBOX_DEB:-$WORK/busybox-static_1.37.0-7ubuntu1_arm64.deb}
BUSYBOX_URL=https://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/busybox-static_1.37.0-7ubuntu1_arm64.deb
BUSYBOX_SHA256=fcf50794faf920455895d7ef103d1c54b9ebf7f18d2e52982dbf3903b7769592

DROPBEAR_TARBALL=${DROPBEAR_TARBALL:-$WORK/dropbear-2026.94.tar.bz2}
DROPBEAR_URL=https://matt.ucc.asn.au/dropbear/releases/dropbear-2026.94.tar.bz2
DROPBEAR_SHA256=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81

PUBKEY=${PUBKEY:-$HOME/.ssh/id_ed25519.pub}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required host tool: $1"; }

echo "=== Omnipha SM7635 Mainline Boot Image Builder ==="
echo "Source root:   $ROOT"
echo "Output dir:    $OUT"
echo "Kernel build:  $KERNEL_OUT"

# Verify required host tools
for tool in mkbootimg python3 cpio gzip sha256sum dpkg-deb curl file fakeroot dtc tar make aarch64-linux-gnu-gcc; do
	need "$tool"
done

# Check / build kernel and DTBs if needed
DTB_PRO="$KERNEL_OUT/arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dtb"
DTB_AST="$KERNEL_OUT/arch/arm64/boot/dts/qcom/milos-nothing-asteroids.dtb"
DTB_FP6="$KERNEL_OUT/arch/arm64/boot/dts/qcom/milos-fairphone-fp6.dtb"
KERNEL_IMAGE="$KERNEL_OUT/arch/arm64/boot/Image"

if [ ! -s "$KERNEL_IMAGE" ] || [ ! -s "$DTB_PRO" ] || [ ! -s "$DTB_AST" ] || [ ! -s "$DTB_FP6" ]; then
	echo "Kernel Image or DTBs missing under $KERNEL_OUT; resolving config and compiling..."
	mkdir -p "$KERNEL_OUT"
	make -C "$ROOT" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig omnipha_usb_gadget.config
	make -C "$ROOT" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
	make -C "$ROOT" -j "$JOBS" O="$KERNEL_OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
		Image qcom/milos-nothing-asteroids.dtb qcom/milos-nothing-asteroids-pro.dtb \
		qcom/milos-fairphone-fp6.dtb
fi

[ -s "$KERNEL_IMAGE" ] || die "missing built kernel: $KERNEL_IMAGE"
[ -s "$DTB_PRO" ] || die "missing built DTB: $DTB_PRO"
[ -s "$DTB_AST" ] || die "missing built DTB: $DTB_AST"
[ -s "$DTB_FP6" ] || die "missing built DTB: $DTB_FP6"
[ -f "$KERNEL_OUT/.config" ] || die "missing kernel config: $KERNEL_OUT/.config"

# Verify kernel config includes required USB gadget and ConfigFS drivers as built-in (=y)
for option in CONFIG_USB_GADGET CONFIG_CONFIGFS_FS CONFIG_USB_CONFIGFS \
	CONFIG_USB_CONFIGFS_NCM CONFIG_USB_F_NCM CONFIG_USB_CONFIGFS_ECM \
	CONFIG_USB_F_ECM CONFIG_USB_DWC3 CONFIG_USB_DWC3_QCOM \
	CONFIG_PHY_SNPS_EUSB2 CONFIG_PHY_QCOM_EUSB2_REPEATER \
	CONFIG_DRM_SIMPLEDRM CONFIG_FRAMEBUFFER_CONSOLE CONFIG_VT \
	CONFIG_VT_CONSOLE CONFIG_FONT_TER16x32; do
	grep -qx "$option=y" "$KERNEL_OUT/.config" || die "kernel config missing built-in $option=y"
done

mkdir -p "$OUT" "$WORK"

# Verify host SSH public key
[ -s "$PUBKEY" ] || die "missing public key file: $PUBKEY (set PUBKEY=<path>)"
python3 - "$PUBKEY" <<'PY'
import base64
import pathlib
import sys

key = pathlib.Path(sys.argv[1]).read_text().strip()
fields = key.split()
if len(fields) not in (2, 3) or fields[0] != "ssh-ed25519":
    raise SystemExit("expected valid ssh-ed25519 public key")
try:
    data = base64.b64decode(fields[1], validate=True)
except ValueError as exc:
    raise SystemExit("invalid public key base64 encoding") from exc
if not data.startswith(b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20") or len(data) != 51:
    raise SystemExit("invalid ed25519 public key wire format")
PY

# Acquire / verify static busybox deb package
if [ ! -f "$BUSYBOX_DEB" ]; then
	echo "Downloading busybox-static arm64..."
	curl -fL --retry 3 --retry-delay 2 -o "$BUSYBOX_DEB" "$BUSYBOX_URL"
fi
printf '%s  %s\n' "$BUSYBOX_SHA256" "$BUSYBOX_DEB" | sha256sum -c -

# Acquire / verify dropbear tarball
if [ ! -f "$DROPBEAR_TARBALL" ]; then
	echo "Downloading dropbear source tarball..."
	curl -fL --retry 3 --retry-delay 2 -o "$DROPBEAR_TARBALL" "$DROPBEAR_URL"
fi
printf '%s  %s\n' "$DROPBEAR_SHA256" "$DROPBEAR_TARBALL" | sha256sum -c -

# Compile static arm64 dropbear
dropbear_build=$(mktemp -d "$WORK/dropbear-build.XXXXXXXX")
stage=$(mktemp -d "$WORK/bootimg-stage.XXXXXXXX")
trap 'rm -rf "$dropbear_build" "$stage"' EXIT

echo "Compiling static arm64 Dropbear SSH server..."
(
	cd "$dropbear_build"
	tar -xjf "$DROPBEAR_TARBALL" --strip-components=1
	cat >localoptions.h <<'OPTIONS'
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_SVR_PAM_AUTH 0
#define DROPBEAR_SVR_LOCALTCPFWD 0
#define DROPBEAR_SVR_REMOTETCPFWD 0
#define DROPBEAR_DSS 0
#define DO_MOTD 0
OPTIONS
	CC=aarch64-linux-gnu-gcc ./configure --host=aarch64-linux-gnu \
		--enable-static --disable-zlib --disable-syslog \
		--disable-lastlog --disable-wtmp --disable-utmp \
		--disable-pututline --disable-pututxline >/dev/null
	make -j "$JOBS" PROGRAMS=dropbear >/dev/null
)

dropbear_bin="$dropbear_build/dropbear"
[ -x "$dropbear_bin" ] || die "dropbear build failed"
file "$dropbear_bin" | grep -q 'ARM aarch64' || die "dropbear binary is not aarch64"
file "$dropbear_bin" | grep -q 'statically linked' || die "dropbear binary is not statically linked"

if command -v qemu-aarch64 >/dev/null 2>&1; then
	qemu-aarch64 "$dropbear_bin" -V 2>&1 | grep -q 'v2026.94' || die "dropbear smoke test under qemu-aarch64 failed"
fi

# Compile static arm64 restart2 helper
[ -f "$ROOT/initramfs/restart2.c" ] || die "missing $ROOT/initramfs/restart2.c"
aarch64-linux-gnu-gcc -nostdlib -static -O2 -Wall -Wextra "$ROOT/initramfs/restart2.c" -o "$stage/restart2"
file "$stage/restart2" | grep -q 'ARM aarch64' || die "restart2 is not aarch64"
file "$stage/restart2" | grep -q 'statically linked' || die "restart2 is not static"

# Assemble initramfs root filesystem
echo "Assembling initramfs filesystem tree..."
mkdir -p "$stage/package" "$stage/root/bin" "$stage/root/sbin" \
	"$stage/root/dev/pts" "$stage/root/proc" \
	"$stage/root/sys/kernel/config" "$stage/root/run" \
	"$stage/root/etc" "$stage/root/root/.ssh" "$stage/root/tmp" \
	"$stage/root/var/run" "$stage/root/usr/share/doc/dropbear"

chmod 0755 "$stage/root" "$stage/root"/* "$stage/root/dev/pts" \
	"$stage/root/sys/kernel" "$stage/root/sys/kernel/config" \
	"$stage/root/usr" "$stage/root/usr/share" \
	"$stage/root/usr/share/doc" "$stage/root/usr/share/doc/dropbear"
chmod 0700 "$stage/root/root" "$stage/root/root/.ssh"
chmod 1777 "$stage/root/tmp"

# Extract busybox
dpkg-deb -x "$BUSYBOX_DEB" "$stage/package"
busybox="$stage/package/usr/bin/busybox"
[ -f "$busybox" ] || die "busybox binary not found in deb package"
file "$busybox" | grep -q 'ARM aarch64' || die "busybox is not aarch64"
file "$busybox" | grep -q 'statically linked' || die "busybox is not static"
install -m 0755 "$busybox" "$stage/root/bin/busybox"

# Install busybox symlinks
for applet in sh ip sleep mount mkdir mknod ln hostname setsid cttyhack cat grep uname reboot tr seq ps getty login; do
	ln -sf busybox "$stage/root/bin/$applet"
done
ln -sf ../bin/busybox "$stage/root/sbin/init"

# Install dropbear & licenses
install -m 0755 "$dropbear_bin" "$stage/root/bin/dropbear"
install -m 0644 "$dropbear_build/LICENSE" "$stage/root/usr/share/doc/dropbear/LICENSE"
install -m 0644 "$dropbear_build/libtomcrypt/LICENSE" "$stage/root/usr/share/doc/dropbear/LibTomCrypt-LICENSE"
install -m 0644 "$dropbear_build/libtommath/LICENSE" "$stage/root/usr/share/doc/dropbear/LibTomMath-LICENSE"

# Install restart2 helper
install -m 0755 "$stage/restart2" "$stage/root/bin/restart2"

# Install init script
[ -f "$ROOT/initramfs/init" ] || die "missing $ROOT/initramfs/init"
install -m 0755 "$ROOT/initramfs/init" "$stage/root/init"

# Inject host public key into authorized_keys (strictly one key, mode 0600)
python3 - "$PUBKEY" "$stage/root/root/.ssh/authorized_keys" <<'PY'
import pathlib
import sys

key = pathlib.Path(sys.argv[1]).read_text().strip()
fields = key.split()
out = pathlib.Path(sys.argv[2])
out.write_text(" ".join(fields[:2]) + "\n")
out.chmod(0o600)
PY

# Create reproducible cpio archive under fakeroot
echo "Creating reproducible cpio archive..."
cat >"$stage/archive.sh" <<'SCRIPT'
set -eu
root=$1
mknod "$root/dev/console" c 5 1
mknod "$root/dev/null" c 1 3
mknod "$root/dev/zero" c 1 5
mknod "$root/dev/kmsg" c 1 11
mknod "$root/dev/ptmx" c 5 2
mknod "$root/dev/tty" c 5 0
mknod "$root/dev/tty0" c 4 0
mknod "$root/dev/tty1" c 4 1
cd "$root"
find . -exec touch -h -d '@0' {} +
find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --reproducible --owner=0:0 --quiet
SCRIPT
chmod 0755 "$stage/archive.sh"

fakeroot -- bash "$stage/archive.sh" "$stage/root" >"$stage/initramfs.cpio"
gzip -n -9 -c "$stage/initramfs.cpio" >"$OUT/initramfs.cpio.gz"
gzip -n -9 -c "$KERNEL_IMAGE" >"$OUT/Image.gz"
cp "$DTB_PRO" "$OUT/dtb.img"

# Prepare vendor bootconfig
printf '%s\n' \
	'androidboot.hardware=qcom' \
	'androidboot.memcg=1' \
	'androidboot.usbcontroller=a600000.usb' \
	'androidboot.console=0' >"$stage/bootconfig"

BOOT_CMDLINE='console=tty0 fbcon=font:TER16x32 clk_ignore_unused pd_ignore_unused bootconfig ioremap_guard loglevel=6'
VENDOR_CMDLINE='earlycon keep_bootcon loglevel=8 log_buf_len=1M ignore_loglevel printk.devkmsg=on panic=-1 bootconfig'

echo "Packaging Android Header v4 boot images..."

# 1. boot.img: Header v4, gzipped mainline Image, empty generic ramdisk
mkbootimg --header_version 4 --pagesize 4096 \
	--base 0x00000000 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
	--dtb_offset 0x0000000001f00000 \
	--os_version 0.0.0 --os_patch_level 0 \
	--kernel "$OUT/Image.gz" \
	--cmdline "$BOOT_CMDLINE" \
	--output "$OUT/boot.img"

# 2. init_boot.img: Header v4, empty kernel, generic ramdisk
: >"$stage/empty-kernel"
mkbootimg --header_version 4 --pagesize 4096 \
	--base 0x00000000 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
	--dtb_offset 0x0000000001f00000 \
	--os_version 0.0.0 --os_patch_level 0 \
	--kernel "$stage/empty-kernel" \
	--ramdisk "$OUT/initramfs.cpio.gz" \
	--cmdline '' \
	--output "$OUT/init_boot.img"

# 3. vendor_boot.img: Header v4, vendor ramdisk, DTB, vendor cmdline & bootconfig
mkbootimg --header_version 4 --pagesize 4096 \
	--base 0x00000000 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
	--dtb_offset 0x0000000001f00000 \
	--os_version 0.0.0 --os_patch_level 0 \
	--kernel "$stage/empty-kernel" \
	--dtb "$OUT/dtb.img" \
	--vendor_cmdline "$VENDOR_CMDLINE" \
	--vendor_ramdisk "$OUT/initramfs.cpio.gz" \
	--vendor_bootconfig "$stage/bootconfig" \
	--vendor_boot "$OUT/vendor_boot.img"

# 4. boot-standalone.img: Header v4 with embedded generic ramdisk (for fastboot boot temporary boot)
mkbootimg --header_version 4 --pagesize 4096 \
	--base 0x00000000 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
	--dtb_offset 0x0000000001f00000 \
	--os_version 0.0.0 --os_patch_level 0 \
	--kernel "$OUT/Image.gz" \
	--ramdisk "$OUT/initramfs.cpio.gz" \
	--cmdline "$BOOT_CMDLINE $VENDOR_CMDLINE" \
	--output "$OUT/boot-standalone.img"

# Compute and record hashes
(
	cd "$OUT"
	sha256sum boot.img init_boot.img vendor_boot.img boot-standalone.img \
		dtb.img Image.gz initramfs.cpio.gz
) | tee "$OUT/bootimg-sha256.txt"

echo "=== Packaging completed successfully ==="
