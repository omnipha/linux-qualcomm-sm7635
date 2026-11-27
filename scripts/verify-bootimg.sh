#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Unpack-and-compare verification for Omnipha SM7635 Mainline boot images
#
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${WORK:-$HOME/sm7635-build}
OUT=${OUT:-$WORK/out-mainline}
KERNEL_OUT=${KERNEL_OUT:-$ROOT/out}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

echo "=== Omnipha SM7635 Mainline Boot Image Verification ==="
echo "Artifacts dir: $OUT"

for tool in unpack_bootimg python3 cpio gzip sha256sum file mktemp fakeroot; do
	need "$tool"
done

# Check required built artifacts exist
for artifact in "$OUT/boot.img" "$OUT/init_boot.img" "$OUT/vendor_boot.img" \
	"$OUT/boot-standalone.img" "$OUT/dtb.img" "$OUT/Image.gz" \
	"$OUT/initramfs.cpio.gz" "$OUT/bootimg-sha256.txt"; do
	[ -f "$artifact" ] || die "missing artifact: $artifact"
done

# 1. Verify recorded SHA-256 checksums
echo "Checking SHA-256 checksums in $OUT/bootimg-sha256.txt..."
( cd "$OUT" && sha256sum -c bootimg-sha256.txt )

# 2. Unpack boot images into scratch directories
scratch=$(mktemp -d "$WORK/bootimg-verify.XXXXXXXX")
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/boot" "$scratch/init_boot" "$scratch/vendor_boot" \
	"$scratch/standalone" "$scratch/initramfs"

unpack_bootimg --boot_img "$OUT/boot.img" --out "$scratch/boot" >/dev/null
unpack_bootimg --boot_img "$OUT/init_boot.img" --out "$scratch/init_boot" >/dev/null
unpack_bootimg --boot_img "$OUT/vendor_boot.img" --out "$scratch/vendor_boot" >/dev/null
unpack_bootimg --boot_img "$OUT/boot-standalone.img" --out "$scratch/standalone" >/dev/null

# 3. Deep Python unpack-and-compare validator
python3 - "$OUT/boot.img" "$OUT/init_boot.img" "$OUT/vendor_boot.img" \
	"$OUT/boot-standalone.img" "$OUT/Image.gz" "$OUT/initramfs.cpio.gz" \
	"$OUT/dtb.img" "$scratch/boot/kernel" "$scratch/init_boot/ramdisk" \
	"$scratch/vendor_boot/dtb" "$scratch/vendor_boot/vendor_ramdisk00" \
	"$scratch/standalone/kernel" "$scratch/standalone/ramdisk" \
	"$KERNEL_OUT/arch/arm64/boot/Image" <<'PY'
import gzip
import hashlib
import pathlib
import struct
import sys

(boot_path, init_boot_path, vendor_boot_path, standalone_path,
 kernel_gz_path, ramdisk_gz_path, dtb_path,
 unpacked_boot_kernel, unpacked_init_ramdisk,
 unpacked_vendor_dtb, unpacked_vendor_ramdisk,
 unpacked_sa_kernel, unpacked_sa_ramdisk,
 raw_kernel_path) = [pathlib.Path(p) for p in sys.argv[1:15]]

def check(name, condition):
    status = "OK" if condition else "FAIL"
    print(f"  [{status}] {name}")
    if not condition:
        sys.exit(f"Verification failure: {name}")

print("\n--- Verifying Boot Image Headers and Payloads ---")

boot_data = boot_path.read_bytes()
init_boot_data = init_boot_path.read_bytes()
vendor_boot_data = vendor_boot_path.read_bytes()
standalone_data = standalone_path.read_bytes()
kernel_gz = kernel_gz_path.read_bytes()
ramdisk_gz = ramdisk_gz_path.read_bytes()
dtb_data = dtb_path.read_bytes()

# Verify boot.img (Header v4)
check("boot.img magic ANDROID!", boot_data[:8] == b"ANDROID!")
boot_hdr_ver = struct.unpack_from("<I", boot_data, 40)[0]
boot_hdr_size = struct.unpack_from("<I", boot_data, 20)[0]
boot_kernel_size = struct.unpack_from("<I", boot_data, 8)[0]
boot_ramdisk_size = struct.unpack_from("<I", boot_data, 12)[0]
boot_sig_size = struct.unpack_from("<I", boot_data, 1580)[0]

check("boot.img header version == 4", boot_hdr_ver == 4)
check("boot.img header size == 1584", boot_hdr_size == 1584)
check("boot.img signature size == 0", boot_sig_size == 0)
check("boot.img generic ramdisk is empty (size == 0)", boot_ramdisk_size == 0)
check("boot.img kernel size matches Image.gz length", boot_kernel_size == len(kernel_gz))
check("boot.img unpacked kernel byte-identical to Image.gz", unpacked_boot_kernel.read_bytes() == kernel_gz)

# Decompress and verify against raw uncompressed Image if available
if raw_kernel_path.is_file():
    decompressed = gzip.decompress(unpacked_boot_kernel.read_bytes())
    check("boot.img decompressed kernel byte-identical to raw Image", decompressed == raw_kernel_path.read_bytes())

# Verify init_boot.img (Header v4)
check("init_boot.img magic ANDROID!", init_boot_data[:8] == b"ANDROID!")
ib_hdr_ver = struct.unpack_from("<I", init_boot_data, 40)[0]
ib_hdr_size = struct.unpack_from("<I", init_boot_data, 20)[0]
ib_kernel_size = struct.unpack_from("<I", init_boot_data, 8)[0]
ib_ramdisk_size = struct.unpack_from("<I", init_boot_data, 12)[0]

check("init_boot.img header version == 4", ib_hdr_ver == 4)
check("init_boot.img kernel is empty (size == 0)", ib_kernel_size == 0)
check("init_boot.img ramdisk size matches initramfs.cpio.gz length", ib_ramdisk_size == len(ramdisk_gz))
check("init_boot.img unpacked ramdisk byte-identical to initramfs.cpio.gz", unpacked_init_ramdisk.read_bytes() == ramdisk_gz)

# Verify vendor_boot.img (Header v4)
check("vendor_boot.img magic VNDRBOOT", vendor_boot_data[:8] == b"VNDRBOOT")
vb_hdr_ver = struct.unpack_from("<I", vendor_boot_data, 8)[0]
vb_page_size, vb_kaddr, vb_raddr = struct.unpack_from("<III", vendor_boot_data, 12)
vb_ramdisk_size = struct.unpack_from("<I", vendor_boot_data, 24)[0]
vb_dtb_size = struct.unpack_from("<I", vendor_boot_data, 2100)[0]
vb_dtb_addr = struct.unpack_from("<Q", vendor_boot_data, 2104)[0]

check("vendor_boot.img header version == 4", vb_hdr_ver == 4)
check("vendor_boot.img page size == 4096", vb_page_size == 4096)
check("vendor_boot.img geometry offsets (0x8000, 0x1000000, 0x1f00000)",
      (vb_kaddr, vb_raddr, vb_dtb_addr) == (0x8000, 0x1000000, 0x1f00000))
check("vendor_boot.img dtb size matches DTB length", vb_dtb_size == len(dtb_data))
check("vendor_boot.img unpacked DTB byte-identical to dtb.img", unpacked_vendor_dtb.read_bytes() == dtb_data)
check("vendor_boot.img unpacked vendor ramdisk byte-identical to initramfs.cpio.gz",
      unpacked_vendor_ramdisk.read_bytes() == ramdisk_gz)

# Verify standalone boot image
check("boot-standalone.img magic ANDROID!", standalone_data[:8] == b"ANDROID!")
sa_hdr_ver = struct.unpack_from("<I", standalone_data, 40)[0]
check("boot-standalone.img header version == 4", sa_hdr_ver == 4)
check("boot-standalone.img unpacked kernel byte-identical to Image.gz", unpacked_sa_kernel.read_bytes() == kernel_gz)
check("boot-standalone.img unpacked ramdisk byte-identical to initramfs.cpio.gz", unpacked_sa_ramdisk.read_bytes() == ramdisk_gz)

# Verify DTB magic and Nothing Phone (3a) Pro model in DTB
check("DTB starts with FDT magic (0xd00dfeed)", dtb_data[:4] == b"\xd0\x0d\xfe\xed")
check("DTB contains 'Nothing Phone (3a) Pro' model string", b"Nothing Phone (3a) Pro" in dtb_data)
check("DTB contains 'simple-framebuffer' compatible", b"simple-framebuffer" in dtb_data)
PY

# 4. Deep inspection of the packed initramfs cpio content and security hygiene
echo ""
echo "--- Auditing Initramfs Contents and Security Hygiene ---"

python3 - "$OUT/initramfs.cpio.gz" "$ROOT/initramfs/init" <<'PY'
import base64
import gzip
import io
import os
import pathlib
import stat
import struct
import subprocess
import sys

cpio_gz_path = pathlib.Path(sys.argv[1])
source_init = pathlib.Path(sys.argv[2])

def check(name, condition):
    status = "OK" if condition else "FAIL"
    print(f"  [{status}] {name}")
    if not condition:
        sys.exit(f"Verification failure: {name}")

# Parse cpio newc archive
data = gzip.decompress(cpio_gz_path.read_bytes())
pos = 0
entries = {}
while pos < len(data):
    magic = data[pos:pos+6]
    if magic not in (b"070701", b"070702"):
        break
    mode = int(data[pos+14:pos+22], 16)
    uid = int(data[pos+22:pos+30], 16)
    gid = int(data[pos+30:pos+38], 16)
    mtime = int(data[pos+46:pos+54], 16)
    filesize = int(data[pos+54:pos+62], 16)
    rmaj = int(data[pos+78:pos+86], 16)
    rmin = int(data[pos+86:pos+94], 16)
    namesize = int(data[pos+94:pos+102], 16)
    name = data[pos+110:pos+110+namesize-1].decode("utf-8", "replace")
    if name == "TRAILER!!!":
        break
    pos += 110 + namesize
    if pos % 4:
        pos += 4 - (pos % 4)
    file_bytes = data[pos:pos+filesize]
    pos += filesize
    if pos % 4:
        pos += 4 - (pos % 4)
    entries[name] = {
        "mode": mode,
        "uid": uid,
        "gid": gid,
        "mtime": mtime,
        "rmaj": rmaj,
        "rmin": rmin,
        "data": file_bytes,
    }

# Check reproducibility of all entries
non_reproducible = [
    n for n, e in entries.items()
    if e["uid"] != 0 or e["gid"] != 0 or e["mtime"] != 0
]
check("all initramfs entries have uid=0, gid=0, and mtime=0 (reproducible)", len(non_reproducible) == 0)

# Check character device nodes
expected_devs = {
    "dev/console": (5, 1),
    "dev/kmsg": (1, 11),
    "dev/null": (1, 3),
    "dev/zero": (1, 5),
    "dev/ptmx": (5, 2),
    "dev/tty": (5, 0),
    "dev/tty0": (4, 0),
    "dev/tty1": (4, 1),
}
for dev_name, (exp_maj, exp_min) in expected_devs.items():
    check(f"entry '{dev_name}' present in cpio", dev_name in entries)
    if dev_name in entries:
        e = entries[dev_name]
        is_chr = stat.S_ISCHR(e["mode"])
        check(f"'{dev_name}' is S_IFCHR with major={exp_maj}, minor={exp_min}",
              is_chr and e["rmaj"] == exp_maj and e["rmin"] == exp_min)

# Check /init
check("entry 'init' present in cpio", "init" in entries)
if "init" in entries:
    e_init = entries["init"]
    check("/init is executable (mode 0755)", stat.S_IMODE(e_init["mode"]) == 0o755)
    check("/init matches source initramfs/init exactly", e_init["data"] == source_init.read_bytes())

# Check binaries: busybox, dropbear, restart2
for bin_name in ["bin/busybox", "bin/dropbear", "bin/restart2"]:
    check(f"entry '{bin_name}' present in cpio", bin_name in entries)
    if bin_name in entries:
        b_data = entries[bin_name]["data"]
        check(f"'{bin_name}' is non-empty ELF", len(b_data) > 0 and b_data[:4] == b"\x7fELF")
        # ELF class 2 (64-bit), machine 183 (0xb7 = aarch64)
        check(f"'{bin_name}' is 64-bit ARM aarch64 ELF", b_data[4] == 2 and struct.unpack_from("<H", b_data, 18)[0] == 183)

# Check authorized_keys
check("entry 'root/.ssh/authorized_keys' present in cpio", "root/.ssh/authorized_keys" in entries)
if "root/.ssh/authorized_keys" in entries:
    ak_entry = entries["root/.ssh/authorized_keys"]
    check("authorized_keys permissions are 0600", stat.S_IMODE(ak_entry["mode"]) == 0o600)
    lines = ak_entry["data"].decode("utf-8").strip().splitlines()
    check("authorized_keys contains exactly one key line", len(lines) == 1)
    fields = lines[0].split()
    check("authorized_keys type is ssh-ed25519", fields[0] == "ssh-ed25519")
    decoded = base64.b64decode(fields[1], validate=True)
    check("authorized_keys is valid ed25519 wire format",
          decoded.startswith(b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20") and len(decoded) == 51)

# Scan for forbidden files: private keys, credentials, firmware blobs
forbidden_exts = {".key", ".pem", ".p12", ".pfx", ".mbn", ".bin", ".elf", ".fw"}
forbidden_names = {"id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", "dropbear_ed25519_host_key"}
found_violations = []
for name in entries:
    base = os.path.basename(name)
    _, ext = os.path.splitext(base)
    if base in forbidden_names or ext.lower() in forbidden_exts:
        if "share/doc/dropbear" not in name:
            found_violations.append(name)

check("no private keys, firmware blobs or secrets found in initramfs", len(found_violations) == 0)
if found_violations:
    print(f"Forbidden files detected: {found_violations}")
PY

echo ""
echo "=== Summary of Verified Artifacts ==="
printf '%-28s %-12s %s\n' "Artifact" "Size (bytes)" "SHA-256"
printf '%-28s %-12s %s\n' "----------------------------" "------------" "----------------------------------------------------------------"
for name in boot.img init_boot.img vendor_boot.img boot-standalone.img dtb.img Image.gz initramfs.cpio.gz; do
	path="$OUT/$name"
	size=$(stat -c '%s' "$path")
	sha=$(sha256sum "$path" | cut -d ' ' -f 1)
	printf '%-28s %-12s %s\n' "$name" "$size" "$sha"
done

echo ""
echo "=== All unpack-and-compare verification checks PASSED ==="
