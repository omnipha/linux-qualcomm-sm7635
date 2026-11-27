# Bringup evidence: Nothing Phone (3a) / (3a) Pro on SM7635 (Milos)

Host-side source and archive evidence only. Nothing in this file claims a
mainline boot; on-device measurements listed below were taken on the vendor
kernel or in userspace and are labeled as such. Raw archives (stock DTB/DTS
decompiles, captures) stay in the private device record; this file carries
only shareable hardware facts, hashes and dates.

## Source references

- Nothing's published Android 6.1 tree, commit
  [`d5f5f965fd0b478eaf4eb63fd984c5a4a92135a7`](https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635/commit/d5f5f965fd0b478eaf4eb63fd984c5a4a92135a7):
  [`volcano-qrd.dtsi`](https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635/blob/d5f5f965fd0b478eaf4eb63fd984c5a4a92135a7/arch/arm64/boot/dts/vendor/qcom/volcano-qrd.dtsi)
  specifies PM7550 L22 at 3.3 V and the Focaltech SPI node and supplies below.
  Its [Pro overlay](https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635/blob/d5f5f965fd0b478eaf4eb63fd984c5a4a92135a7/arch/arm64/boot/dts/vendor/qcom/volcano-qrd-pro-overlay.dts)
  includes that common file and uses OEM ID 2. This is vendor source evidence,
  not proof of Mainline compatibility or a live voltage measurement.

## Unit and stock identity

- Reference unit: Omnipha `mb003`, Nothing Phone (3a) Pro (A059P).
- Stock live FDT read from the unit on 2026-10-19, archived
  (sha256 `7310d10a9dc9c78a7c5bedd20375fd5506d0e7cbdc9ed7eac47a83651c259c6c`):
  - `model = "Qualcomm Technologies, Inc. Volcano QRD Pro"`
  - `compatible = "qcom,volcano-qrd", "qcom,volcano", "qcom,volcanop-qrd", "qcom,volcanop", "qcom,qrd"`
  - `qcom,msm-id = <640 0x10000>, <641 0x10000>, <636 0x10000>` (VOLCANO6, VOLCANO6P, VOLCANO)
  - `qcom,board-id = <11 0>`; no `qcom,oem-id` at the FDT root.
- In the archived stock DTBO image, entry 64 is labeled `Volcano QRD` and has
  `qcom,oem-id = <1>` (sha256
  `57afcf982caa1b5907f0154eaa3dc75abff8a045a25789c59ab5fb777506ca3a`);
  entry 65 is labeled `Volcano QRD Pro` and has `qcom,oem-id = <2>` (sha256
  `93be04b6e20914fd1546ad314e351199bb3e6b6a71c2555ef956175164909ae2`).
  Both have the same `qcom,board-id` and `qcom,msm-id` values shown above.
  The Pro model matches the archived live FDT, but selection by the bootloader
  has not been observed. Both overlays contain the same Focaltech touch-node
  properties before fixups; their remaining hardware cannot be assumed to be
  identical.
- Upstream Linux 7.3 ships `milos-nothing-asteroids.dts` with
  `model = "Nothing Phone (3a)"` and no oem-id. The historical, self-declared
  untested tree `sm7635-mainline/linux` (commit
  `e3802ef3a34225e1057e8dc5b52abb26d052b9f0`, branch `wip-next-20250502`)
  comments the same board file as "Nothing Phone (3a) Pro" and sets
  `qcom,oem-id = <2>` with the comment "(3a) - 1; (3a) Pro - 2".
  Whether the upstream tree matches the Pro unit is therefore unproven; treat
  Pro-specific wiring as an open measurement point.

## Peripherals measured on the vendor kernel (not mainline)

- Touchscreen: Focaltech FTS, stock node `focaltech@0` under
  `spi@a80000` (`qcom,spi-geni`, SPI0), `compatible = "focaltech,fts_ts"`,
  `reg = <0>`, `spi-max-frequency = <0xb71b00>` (12 MHz),
  `focaltech,max-touch-number = <0x0a>`,
  `focaltech,display-coords = <0 0 1080 2392>`. Resolving stock phandle
  `0x65` identifies the SoC TLMM at `/soc/pinctrl@f000000`, not a PMIC GPIO
  controller: interrupt uses TLMM GPIO 19 and reset uses GPIO 20. `vci-supply`
  resolves to PM7550 L22, specified as 3.3 V in the stock live FDT;
  `vddio-supply` resolves to PM7550 L11 at 1.8 V. These are DT properties,
  not measured voltages. The upstream Nothing tree sets PM7550 L22
  (`vreg_l22b`) to 3.2 V. The experimental Pro tree specifies 3.3 V from
  stock DT, but neither value has been measured on the physical rail and the
  discrepancy must be resolved before device testing or enabling touch.
  Touch was measured working on vendor kernel 6.1 with the vendor module
  `focaltech_fts.ko` (device record boot `8dc2622e`, 2026-11-07). Required
  module order on the vendor kernel:
  `msm_gpi` -> `touchpanel_event_notify` -> `spi-msm-geni` -> `focaltech_fts`;
  loading `spi-msm-geni` without `msm_gpi` crashed the SoC into Qualcomm crash
  mode. Vendor behavior only; it says nothing about a mainline driver.
- Display: stock device tree overlays name two DSI panel variants,
  "ft8726 lcd video mode dsi focaltech panel with DSC" and
  "rm69220 amoled vid mode dsi BOE panel with DSC". The display works on the
  vendor kernel (Phosh, 1080x2392). Earlier mainline-style panel experiments
  on a custom kernel bound a BOE panel node while the glass stayed dark
  (device record runs 87/88, 2026-11-01). The panel variant fitted to the
  reference unit is not conclusively established in public evidence.
  For early console via bootloader continuous splash (`simple-framebuffer`),
  see [framebuffer-evidence.md](framebuffer-evidence.md).
- Camera: Sony IMX355 ultra-wide captured in userspace through the vendor
  kernel TFE/RDI path (1680x1260 RAW10); see the private device record and
  `phone-second-life` `patches/mb003-camera`. Mainline has
  `drivers/media/i2c/imx355.c`, but the upstream asteroids tree enables no
  camera path. A capture returning a buffer alone is not proof of a usable
  image or a mainline camera pipeline.
- WLAN, audio codecs, NFC, haptics: measured or present on the vendor kernel
  per the device record; none of them is enabled by the upstream asteroids
  device tree.

## Mainline 7.3 state for this board

- `milos-nothing-asteroids.dts` enables: PMIC regulators, gpio-keys (assist,
  volume up), pmic-glink with USB-C connector, ramoops, awinic glyph LED,
  PMIC flash LED, pon power/resin keys, QUP wrappers, remoteprocs with
  firmware names `qcom/milos/nothing/asteroids/*.mbn`, uart5 and USB 2.0 HS.
- It does not enable: DSI/display/panel, the SPI0 touchscreen node, camera,
  WLAN or audio machines.
- `spi0: spi@a80000` exists in `milos.dtsi` with `status = "disabled"` and no
  child node; the SoC node is the right place for the controller, the touch
  child node belongs in the board tree.
- No mainline driver matches `focaltech,fts_ts`: `edt-ft5x06` binds only I2C
  Focaltech/EDT compatibles, while the stock controller sits on SPI with a
  vendor protocol. Touch on mainline needs driver work; untested.
- Firmware files referenced by the remoteproc nodes are not part of this
  repository and must not be added.

## Reachability

- 2026-11-22: a read-only live check failed; the device was not reachable.
  No device writes or reboots were performed. The dated vendor-kernel
  measurements above remain the only on-device evidence.

## Consequences for Omnipha work

- Board-specific additions (touch child node, panel, camera, WLAN) go into a
  device tree on branch `omnipha`, never into `milos.dtsi`.
- Each addition needs its own measured evidence per `AGENTS.md`; the vendor
  kernel measurements above are evidence for vendor behavior only.
- The experimental Pro tree includes the upstream Nothing tree and overrides
  only the model, compatible and stock-DT L22 voltage. It does not enable
  touch; its inherited wiring, boot and L22 behavior remain unverified.
- Open measurement points: actual bootloader DTBO selection, the upstream
  board tree's applicability to Pro, the fitted panel variant, the L22
  voltage discrepancy and the SPI touch protocol against a mainline driver.
