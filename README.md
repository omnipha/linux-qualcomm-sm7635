# Linux on Qualcomm SM7635 / Milos

Shared mainline Linux kernel source for devices using Qualcomm SM7635
(Snapdragon 7s Gen 3, also known as Milos or Volcano). This is a platform
repository: device-specific support can be added for multiple manufacturers.
It is not an installer, a boot image, or a claim that any phone is supported.

## Source and branches

- Linux upstream: https://github.com/torvalds/linux
- Initial baseline: Linux v7.3, commit `c03c1a14507dfaf8b856c2608f9ac216021fc222`.
- `upstream`: pinned, unmodified upstream baseline. Do not add Omnipha commits.
- `omnipha`: shared and device-specific development based on that baseline.
- The separate [linux-sm7635](https://github.com/omnipha/linux-sm7635)
  records the previous Nothing vendor-kernel investigation.
- Historical reference only: [sm7635-mainline/linux](https://github.com/sm7635-mainline/linux/tree/wip-next-20250502), an untested Linux 6.15-rc4 work-in-progress.

## Device trees

| Source | Model | Origin and verification |
|---|---|---|
| `milos-nothing-asteroids.dts` | Nothing Phone (3a) | Upstream baseline; built and DT-schema checked, not boot-tested here. |
| `milos-nothing-asteroids-pro.dts` | Nothing Phone (3a) Pro | Omnipha experimental variant; built and DT-schema checked, inherited wiring and boot are unverified. |
| `milos-fairphone-fp6.dts` | The Fairphone (Gen. 6) | Upstream baseline; built and DT-schema checked, not device-tested here. |

SoC-wide definitions are in `arch/arm64/boot/dts/qcom/milos.dtsi`.
The device tree expresses hardware data, not verification of working hardware.
Other SM7635/Milos devices can be added as their hardware and firmware are
investigated; do not infer device compatibility merely from a shared SoC.

## Build

The host requires a kernel build toolchain including GNU make, GCC for AArch64,
flex, bison, bc, OpenSSL development headers, and device-tree build tools.
Example, from the root of this checkout:

```sh
# Baseline build
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make -j"$(nproc)" O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    Image qcom/milos-nothing-asteroids.dtb qcom/milos-nothing-asteroids-pro.dtb \
    qcom/milos-fairphone-fp6.dtb

# Or with USB gadget device-mode networking fragment for headless bring-up:
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig omnipha_usb_gadget.config
make -j"$(nproc)" O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    Image qcom/milos-nothing-asteroids.dtb qcom/milos-nothing-asteroids-pro.dtb \
    qcom/milos-fairphone-fp6.dtb
```

These are build instructions, not a tested boot procedure. See
[baseline and evidence](Documentation/omnipha-sm7635/baseline.md) and
[USB device mode preparation](Documentation/omnipha-sm7635/usb-device-mode.md)
for current verification status. Firmware is not included. Do not reboot or flash a
device without first verifying its identity, backup and recovery path.

## Licensing

Linux is licensed under GPL-2.0 as detailed in [COPYING](COPYING); individual
files have their own SPDX identifiers. Preserve copyright and provenance.
