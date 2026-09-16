# Enable the SAMA7D65's Vivante GC520UL 2D GPU.
#
# sama7d65.dtsi describes gpu@e1480000 completely -- reg, interrupt, bus/core
# clocks, 533 MHz GPU PLL -- but leaves it status = "disabled", and no board DTS
# in the tree references &gpu. The GFX2D node on sam9x7 is disabled the same way,
# so this is an opt-in-per-board convention, not an oversight. Until the node is
# enabled the nano2D driver has nothing to probe and libm2d cannot run at all.
#
# Applied as a kernel patch rather than a devicetree overlay on purpose: the
# overlays here are packed into sama7d65_curiosity.itb and selected by U-Boot's
# detection logic (see the machine's u-boot env), so adding one would mean
# editing dt-overlay-mchp's .its and the boot-time selection. The GPU is an
# always-present SoC block with no board variation, so a plain DTS enable is both
# simpler and closer to how the kernel expects it to be expressed.
#
# Scoped to sama7d65 so other machines built from this layer are untouched.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:sama7d65 = " file://0001-ARM-dts-sama7d65_curiosity-enable-the-2D-GPU.patch"
