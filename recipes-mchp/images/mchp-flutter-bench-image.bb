DESCRIPTION = "Headless image plus Flutter (ivi-homescreen software backend, Skia CPU \
into a DRM dumb buffer) and benchmark apps, for measuring what a Flutter GUI can do on \
this GPU-less SoC."
LICENSE = "MIT"

# Headless base, not mchp-graphics-image: EGT's demo suite is irrelevant here and
# mchp-graphics-image stays the known-good fallback.
require recipes-mchp/images/mchp-headless-image.bb

# The SoC's Vivante GC is 2D-only, so there is no hardware GLES, and software GLES
# was measured unusable (glmark2 Score: 1; llvmpipe segfaults on armv7). This image
# therefore uses no GL at all: ivi-homescreen is built with backend-software +
# software-sink-drm, so Skia's CPU rasteriser writes straight into a DRM dumb
# buffer. See local.conf for the PACKAGECONFIG and the reasoning.
#
# ivi-homescreen           - the embedder (binary: 'homescreen')
# flutter-engine           - armv7 libflutter_engine.so, release/AOT
# *-scroll-bench           - upstream list-scroll FPS benchmark, explicitly
#                            supporting the software backend. This is the Stage C
#                            gate: prove the backend renders before writing anything
#                            custom.
# *-stopwatch-stress-test  - upstream animation stress test
# libdrm-tests             - modetest, to confirm the 800x480 LVDS mode and see what
#                            pixel format the DRM sink actually sets
IMAGE_INSTALL:append = "\
    ivi-homescreen \
    flutter-engine \
    libdrm-tests \
    xkeyboard-config \
    ivi-homescreen-defaults \
    cpufreq-performance \
    flutter-hmi-bench \
    libm2d \
    nano2d \
    kernel-module-nano2d \
    m2d-caps \
"

# The 2D GPU stack is included ahead of any Flutter integration so that one flash
# answers both open questions: the IVI_SW_VSYNC=0 run (which decides whether the
# compositor route has any payoff) needs the Flutter image, and m2d-caps needs the
# GPU. libm2d is also a prerequisite for the dart:ffi route regardless of which
# way that decision goes, so nothing here is speculative.
#
# m2d-caps prints M2D_CAP_STRIDE_ALIGNMENT and friends; the stride alignment
# dictates the row_bytes an m2d-allocated buffer must have before Skia can
# rasterise into it.

# cpufreq-performance pins the governor at boot. The board defaults to
# 'conservative', which idles at 90 MHz of an available 1000 MHz and ramps in small
# steps - the worst case for interactive UI, since a fling or transition can finish
# before the clock climbs. With no GPU, clock speed IS frame rate.
#
# flutter-hmi-bench is the local scene-based benchmark: it isolates one rendering
# cost per scene and prints CSV (build vs raster, median and p95) so a design budget
# comes from measurements rather than impressions.

# ivi-homescreen-defaults ships /etc/profile.d/ivi-homescreen.sh exporting
# IVI_SW_SINK=drm-dumb (without which the backend silently discards every frame)
# and IVI_SW_DRM_FORMAT=rgb565 (measured faster on hardware: matches the panel's
# native 16 bpp, so no per-frame 32->16 conversion and half the scanout write
# bandwidth). Login shells only - a systemd launcher must set them itself.

# FONTS ARE MANDATORY - without them Flutter renders NO TEXT AT ALL.
#
# mchp-headless-image ships no fonts (only libfontconfig1, the library), so
# fontconfig has nothing to resolve and every string draws as nothing. Shapes,
# lines, images and icons still render, which makes this look like a text-layout
# bug rather than a missing-font one: app icons come from MaterialIcons-Regular.otf
# bundled inside each app's flutter_assets, whereas Flutter's default text font is
# NOT bundled on embedded Linux - it is resolved from the system through
# fontconfig. mchp-graphics-image installs liberation/lohit/noto/dejavu, which is
# why EGT renders text and this image initially did not.
#
# fontconfig-utils is included on purpose: fc-list and fc-match on the target are
# the quickest way to tell "no fonts installed" from "fonts present but not matched".
IMAGE_INSTALL:append = "\
    liberation-fonts \
    ttf-dejavu-sans \
    ttf-dejavu-sans-mono \
    ttf-dejavu-serif \
    fontconfig-utils \
"

# xkeyboard-config supplies /usr/share/X11/xkb. Without it libxkbcommon fails at
# startup with "failed to add default include path /usr/share/X11/xkb" and then
# "[SoftwareSeat] XkbKeyboard::Create failed", leaving keyboard input dead. Touch
# is unaffected (the Atmel maXTouch device opens fine), so this does not disturb
# rendering benchmarks - but it does make the keyboard test apps meaningless.

# Benchmark and demo apps. All are pure Dart UI: nothing here needs a platform
# channel, which matters because this build uses 'disable-plugins' (the plugin
# tree does not compile against the software backend).
#
# Deliberately excluded because they cannot work in this configuration, and would
# fail at RUNTIME in ways that look like rendering bugs:
#   flutter-sdk-examples-platform-channel / -platform-view / -texture
#       - these exist to exercise platform channels; with plugins disabled they
#         would throw MissingPluginException
#   ivi-homescreen-mcp-drive-test        - needs BUILD_MCP
#   ivi-homescreen-osgi-activator-test   - needs the OSGi option
#   flutter-sdk-examples-multiple-windows, -integration-tests-windowing-test
#       - multi-window needs the compositor, which is off (same option the HUD
#         wanted, and left off deliberately to keep the present path direct)
IMAGE_INSTALL:append = "\
    ivi-homescreen-scroll-bench \
    ivi-homescreen-stopwatch-stress-test \
    ivi-homescreen-gesture-playground \
    ivi-homescreen-multi-touch-test \
    ivi-homescreen-keyboard-test \
    ivi-homescreen-hardware-keyboard-test \
    ivi-homescreen-watchdog-test \
    flutter-sdk-examples-hello-world \
    flutter-sdk-examples-layers \
    flutter-sdk-dev-integration-tests-flutter-gallery \
    flutter-sdk-dev-integration-tests-ui \
    flutter-sdk-dev-a11y-assessments \
    flutter-sdk-dev-manual-tests \
"

# Public third-party apps from meta-flutter-apps, chosen for appliance / lab-instrument
# character: menu buttons, icons, dense text, vector graphics. These need the
# meta-flutter-apps layer (separate from meta-flutter) plus the S-fix bbappends in
# meta-local/recipes-flutter-apps/apps/ - see CLAUDE.md.
#
# Excluded because they genuinely cannot work here: flutter-samples-simplistic-calculator
# and flutter-samples-provider-shopper both depend on the Linux 'window_size' plugin, and
# with disable-plugins the recipe refuses to build rather than ship an app whose plugins
# are never registered. That refusal is definitive, not a workaround candidate.
IMAGE_INSTALL:append = "\
    flutter-samples-material-3-demo \
    flutter-packages-material-ui-material-ui-examples \
    flutter-packages-cupertino-ui-cupertino-ui-examples \
    flutter-samples-cupertino-gallery \
    flutter-samples-form-app \
    flutter-samples-context-menus \
    flutter-samples-platform-design \
    flutter-samples-navigation-and-routing-bookstore \
    flutter-packages-vector-graphics-example \
    rive-app-rive-flutter-example-rive-example \
    widgetbakery-pixel-snap-example \
"
