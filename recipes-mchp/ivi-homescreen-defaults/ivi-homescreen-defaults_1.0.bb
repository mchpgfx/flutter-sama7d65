SUMMARY = "Default IVI_SW_* environment for the ivi-homescreen software backend"
DESCRIPTION = "Sets the software backend's sink and pixel format so 'homescreen -b <bundle>' \
works and performs correctly without remembering environment variables."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://ivi-homescreen.sh"

# Config only - no compilation, and not machine-specific code.
inherit allarch

do_install() {
    install -d ${D}${sysconfdir}/profile.d
    install -m 0644 ${WORKDIR}/ivi-homescreen.sh ${D}${sysconfdir}/profile.d/ivi-homescreen.sh
}

FILES:${PN} = "${sysconfdir}/profile.d/ivi-homescreen.sh"
