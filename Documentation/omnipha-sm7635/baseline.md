# SM7635 / Milos baseline

## Scope

Shared, mainline-based Qualcomm SM7635 platform source, not a single-phone
fork. Device-specific additions must not change unrelated phone wiring.

## Baseline

- Linux v7.3, commit `c03c1a14507dfaf8b856c2608f9ac216021fc222`.
- Upstream `arch/arm64/boot/dts/qcom/milos.dtsi` describes the SoC.
- Upstream contains `milos-nothing-asteroids.dts` (model: Nothing Phone (3a))
  and `milos-fairphone-fp6.dts` (model: The Fairphone (Gen. 6)). Their mere
  presence does not prove either device boots.
- The separately investigated Nothing Phone (3a) Pro is the initial target;
  applicability of the upstream Nothing device tree to Pro is not proven.
- Older experimental reference: sm7635-mainline/linux commit
  `e3802ef3a34225e1057e8dc5b52abb26d052b9f0`, branch
  `wip-next-20250502`, file `sm7635-nothing-asteroids.dts`. It labels its
  subject Pro and sets `qcom,oem-id` to 2, but the repository warns that the
  branch is untested. These are source observations, not boot evidence.
- Prior device measurements and the working Android-vendor 6.1 kernel are
  documented separately in https://github.com/omnipha/linux-sm7635; those
  measurements do not prove equivalent behavior on upstream Linux 7.3.

## Verification

### Build verification (2026-11-22)

Host build on x86_64 with `aarch64-linux-gnu-gcc` 15.2.0, GNU Make 4.4.1 and
dtc 1.7.2, from branch `omnipha` at commit
`55ad2d8cec4e02f6dcce4b500fd4c547f355d3c1`:

```sh
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make -j4 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    Image qcom/milos-nothing-asteroids.dtb qcom/milos-fairphone-fp6.dtb
```

The build completed without errors. SHA-256 of the outputs:

| artifact | sha256 |
| --- | --- |
| `out/arch/arm64/boot/Image` | `94060c8a9382737c43260b1f68ccf41fe8477927e991b927702d7c002741fd8d` |
| `out/arch/arm64/boot/dts/qcom/milos-nothing-asteroids.dtb` | `020f9b7be25af001958febc0ba15efc87e4c86c25553e3c47f8aa1120304ad4a` |
| `out/arch/arm64/boot/dts/qcom/milos-fairphone-fp6.dtb` | `c3908fe06eeb9e236923b9081639d7f7d18bb10d42848077750b2397c8f5ad6a` |
| `out/.config` | `5ce33c8f5e1db4278b0d74981d54b8eaa354d409b4f36529704024ba0d5c2576` |

This verifies compilation of the unmodified upstream baseline only. It is not
a boot test and not a claim that any device works.

### Device-tree schema check (2026-11-22)

Both compiled baseline DTBs were checked on the host with `dtschema` 2026.9:

```sh
make -j4 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=1 \
    qcom/milos-nothing-asteroids.dtb qcom/milos-fairphone-fp6.dtb
dt-validate -m -u Documentation/devicetree/bindings \
    -p out/Documentation/devicetree/bindings/processed-schema.json \
    out/arch/arm64/boot/dts/qcom/milos-nothing-asteroids.dtb \
    out/arch/arm64/boot/dts/qcom/milos-fairphone-fp6.dtb
```

Both tools produced no schema diagnostics for these DTBs; the DTB hashes above
remained unchanged. As a negative control, removing the root `model` from a
candidate DTB copy caused `dt-validate` to report that required property
missing. The validator still returned exit status 0 in that case; inspect its
output, not only its exit status. This is a schema check, not a hardware test.

### Experimental Nothing Phone (3a) Pro variant (2026-11-22)

On top of `7f13972430247f1278efced8679b46a761984231`, the Omnipha variant
`milos-nothing-asteroids-pro.dts` includes the upstream Phone (3a) tree and
changes only the model, adds an experimental Pro compatible with the existing
board fallback, and sets PM7550 L22 to 3.3 V. The L22 value is from the
archived Pro stock FDT, not a measured rail voltage. It is not proof that the
inherited Phone (3a) wiring is correct on the Pro.

```sh
make -j4 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=1 \
    qcom/milos-nothing-asteroids-pro.dtb qcom/milos-nothing-asteroids.dtb \
    qcom/milos-fairphone-fp6.dtb
make -j4 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    DT_SCHEMA_FILES=arm/qcom.yaml dt_binding_check
```

The new Pro DTB built and all three DTBs passed direct `dt-validate` without
schema diagnostics; the binding and YAML style checks reported no errors.
Comparing the decompiled DTBs showed exactly four changed properties: root
`model`, root `compatible`, and L22 minimum/maximum voltage. The original
Nothing and Fairphone DTB hashes above remained unchanged. The Pro DTB SHA-256
is `25ee4f8dd5789bc679d009712bba0e14d06ac1b8df65131e8d35219b24663228`.

This is an experimental host build only: no device boot, flash, touch driver,
panel support, firmware validation or physical voltage measurement. Bootloader
DT selection and compatibility of inherited wiring remain unverified. Do not
install without independently verifying the device and a recovery path.

### Known device-tree gaps for the Nothing target

The upstream `milos-nothing-asteroids.dts` enables UART, USB, regulators,
remoteprocs and keys, but no display panel, no touchscreen and no camera.
The historical `sm7635-mainline` WIP tree lists those peripherals only as
comments (for example a FocalTech touchscreen on SPI0). Mainline Linux 7.3
has no driver matching the stock touch controller compatible observed on the
device, and the stock panel and camera wiring is not represented upstream.
Any Omnipha device work must therefore add device-specific nodes and, where
needed, driver support on top of measured evidence; the shared SoC tree stays
untouched by board wiring.

## Next checks

1. Compare the upstream Nothing tree, experimental Pro tree and the target's
   stock hardware evidence before proposing device-specific changes. See the
   [Nothing evidence](../nothing-asteroids/bringup-evidence.md), including the
   L22 regulator discrepancy and missing SPI touchscreen driver.
2. ~~Build the upstream baseline and both existing Milos device trees~~ done,
   see build verification above.
3. Mainline USB device-mode preparation: done, see
   [USB device mode documentation](usb-device-mode.md) and the versioned
   fragment `arch/arm64/configs/omnipha_usb_gadget.config`.
4. Before any device test, establish identity, backups and a tested recovery
   path. Test on-device support separately for each device and subsystem.
