SUMMARY = "Print the 2D GPU's libm2d capability values"
DESCRIPTION = "Reads M2D_CAP_* via m2d_get_capability. These constrain any libm2d \
integration - notably the stride alignment a GPU-visible buffer must satisfy before Skia \
can rasterise into it - and are cheaper to read off the hardware than to discover midway \
through an implementation."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://m2d-caps.c"
S = "${WORKDIR}"

DEPENDS = "libm2d"

# pkgconfig is inherited so pkg-config-native lands in the sysroot. Without it the
# $(pkg-config ...) substitution below silently expands to nothing and the link
# fails with "undefined reference to m2d_init" rather than a missing-tool error.
inherit pkgconfig

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o m2d-caps m2d-caps.c \
        `pkg-config --cflags --libs libm2d` -lm2d
}

do_install() {
    install -D -m 0755 ${B}/m2d-caps ${D}${bindir}/m2d-caps
}
