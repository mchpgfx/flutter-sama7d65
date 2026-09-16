SUMMARY = "Menu-driven Flutter demo launcher for the SAMA7D65 Curiosity"
DESCRIPTION = "Supervisor that shows the Flutter demo menu, runs the selected bundle, and \
returns to the menu when the USER button (PC10) is pressed. ivi-homescreen runs one bundle per \
process and holds DRM master, so switching demos requires restarting it - hence a supervisor \
rather than in-app navigation."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://flutter-demo-launcher \
           file://flutter-demo-launcher.service"

# The script defaults to a hardcoded connector name (LVDS-1), overridable via
# DEMO_CONNECTOR in the unit, so this is not machine-neutral.
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "flutter-demo-launcher.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# Everything the script's paths assume. Missing pieces should fail the build, not
# leave a unit restart-looping on the board.
RDEPENDS:${PN} = "\
    ivi-homescreen \
    flutter-engine \
    userbtn-wait \
    flutter-demo-menu \
    flutter-sdk-dev-integration-tests-flutter-gallery \
    flutter-samples-material-3-demo \
"

do_install() {
    install -D -m 0755 ${WORKDIR}/flutter-demo-launcher ${D}${bindir}/flutter-demo-launcher
    install -D -m 0644 ${WORKDIR}/flutter-demo-launcher.service \
        ${D}${systemd_system_unitdir}/flutter-demo-launcher.service
}

FILES:${PN} += "${systemd_system_unitdir}/flutter-demo-launcher.service"
