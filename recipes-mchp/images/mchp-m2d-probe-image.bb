DESCRIPTION = "Headless image plus the 2D GPU stack (nano2D driver + libm2d and its tests), \
to prove the Vivante GC520UL works on this board before any Flutter integration is attempted."
LICENSE = "MIT"

require recipes-mchp/images/mchp-headless-image.bb

# STAGE 0 GATE of the libm2d plan. The SAMA7D65's Vivante GC520UL has never been
# exercised on this board: sama7d65.dtsi ships gpu@e1480000 as status = "disabled"
# and no board DTS referenced it, so nothing has ever bound to it. meta-local's
# linux-mchp bbappend enables the node; this image proves the rest of the stack.
#
# Nothing downstream is worth building until this renders:
#   dmesg | grep -i nano2d          # did the module bind to gpu@e1480000?
#   lsmod | grep nano2d
#   ls /usr/share/m2d/              # test assets, incl. 800x480 for this panel
#   <libm2d test binary>            # see /usr/bin, name comes from test/CMakeLists.txt
#   modetest -M atmel-hlcdc         # confirm the panel is still driven
#
# kernel-module-nano2d sets KERNEL_MODULE_AUTOLOAD, so it should load at boot
# without modprobe.
#
# libm2d is built with -DENABLE_TESTS=1 by meta-mchp and ships 800x480 assets
# (test_pattern_800x480.png, background_800x480.png) that match this panel exactly.
# It lives in meta-mchp's dynamic-layers/openembedded-layer, so meta-oe must be in
# bblayers.conf - it is.
#
# Fonts are included because a headless base has none and anything drawing text
# would silently render nothing; libdrm-tests supplies modetest.
IMAGE_INSTALL:append = "\
    libm2d \
    nano2d \
    kernel-module-nano2d \
    libdrm-tests \
    liberation-fonts \
    fontconfig-utils \
"
