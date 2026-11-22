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

The baseline source has been checked out. A build, device-tree validation and
mainline boot of the Nothing Phone (3a) Pro remain unverified. No files have
been written to a phone as part of this repository setup.

## Next checks

1. Compare the upstream Nothing tree, experimental Pro tree and the target's
   stock hardware evidence before proposing device-specific changes.
2. Build the upstream baseline and both existing Milos device trees; record
   tools, revision and output hashes.
3. Before any device test, establish identity, backups and a tested recovery
   path. Test on-device support separately for each device and subsystem.
