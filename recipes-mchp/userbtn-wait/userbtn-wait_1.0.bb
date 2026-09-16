SUMMARY = "Block until the SAMA7D65 Curiosity USER button (PC10) is pressed"
DESCRIPTION = "Reads the gpio-keys evdev device and exits 0 on a KEY_0 press, which is what the \
board DTS maps PC10 to. Used by flutter-demo-launcher to return from a demo to the menu."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://userbtn-wait.c"
S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o userbtn-wait userbtn-wait.c
}

do_install() {
    install -D -m 0755 ${B}/userbtn-wait ${D}${bindir}/userbtn-wait
}
