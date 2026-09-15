SUMMARY = "Pin the CPU frequency governor to performance at boot"
DESCRIPTION = "The board ships the 'conservative' governor, which idles at the lowest OPP \
(90 MHz of 1000 available on SAMA7D65) and ramps slowly. With no GPU, every pixel is drawn \
by the CPU, so clock speed is frame rate. This pins the maximum."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://cpufreq-performance.service"

inherit systemd allarch

SYSTEMD_SERVICE:${PN} = "cpufreq-performance.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/cpufreq-performance.service \
        ${D}${systemd_system_unitdir}/cpufreq-performance.service
}

FILES:${PN} += "${systemd_system_unitdir}/cpufreq-performance.service"

# Trade-off worth stating: pinning maximum clock raises power draw and die
# temperature continuously. That is right for a benchmark/dev image. A shipped
# product more likely wants 'ondemand' or 'schedutil' with a lowered up-threshold -
# most of the responsiveness without holding 1 GHz permanently.
