DESCRIPTION = "Kiosk image that boots into a Flutter menu offering the Flutter Gallery and \
Material 3 demos, on the 800x480 LVDS panel via ivi-homescreen's software backend \
(Skia CPU -> DRM dumb buffer). The USER button (PC10) returns from a demo to the menu."
LICENSE = "MIT"

require recipes-mchp/images/mchp-headless-image.bb

# flutter-demo-launcher RDEPENDS on the embedder, engine, menu, both demo bundles and
# userbtn-wait, so they arrive transitively. Listed explicitly for legibility.
#
# ivi-homescreen runs ONE bundle per process and holds DRM master, so the launcher is
# a supervisor that restarts it per selection rather than in-app navigation. Only one
# unit may own the display - do not add a second auto-starting homescreen service.
#
# Fonts are NOT optional: mchp-headless-image ships only libfontconfig1 with no font
# files, and Flutter's default text font is resolved from the system via fontconfig.
# Without them every screen renders shapes and icons but NO TEXT, with no error and no
# log line - the bundled MaterialIcons font still works, which makes it look like a
# text-layout bug rather than a missing font.
#
# cpufreq-performance pins the governor; the board ships 'conservative', idling at
# 90 MHz of an available 1000, which is the worst case for interactive UI on a part
# where the CPU draws every pixel.
IMAGE_INSTALL:append = "\
    flutter-demo-launcher \
    flutter-demo-menu \
    userbtn-wait \
    ivi-homescreen \
    flutter-engine \
    flutter-sdk-dev-integration-tests-flutter-gallery \
    flutter-samples-material-3-demo \
    cpufreq-performance \
    liberation-fonts \
    ttf-dejavu-sans \
    ttf-dejavu-sans-mono \
    fontconfig-utils \
    xkeyboard-config \
    libdrm-tests \
"

# Deliberately omitted: ivi-homescreen-defaults, which installs /etc/profile.d and is
# therefore not read by systemd services. The launcher script exports IVI_SW_SINK and
# IVI_SW_DRM_FORMAT itself. Harmless to add if you also want a login shell to run
# homescreen without arguments.
