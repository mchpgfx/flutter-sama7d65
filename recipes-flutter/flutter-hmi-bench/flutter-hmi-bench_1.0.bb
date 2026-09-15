SUMMARY = "Scene-based Flutter render benchmark for GPU-less targets"
DESCRIPTION = "Cycles isolated rendering scenes (gauges, lists, status, charts, images \
and saveLayer effects) and reports build/raster frame timings as CSV, so a GUI design \
budget can be derived from measurements rather than impressions."
AUTHOR = "local"
SECTION = "graphics"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# The whole app directory is copied in from files/. No third-party Dart packages:
# it keeps the pub cache trivial and, more importantly, guarantees no plugin
# dependency - this build uses disable-plugins, and any app pulling a Linux plugin
# is refused outright by the recipe machinery.
SRC_URI = "file://flutter_hmi_bench"

S = "${WORKDIR}"
PUBSPEC_APPNAME = "flutter_hmi_bench"
FLUTTER_APPLICATION_PATH = "flutter_hmi_bench"

# AOT. Verify the result with:
#   readelf -h .../flutter_hmi_bench/*/release/lib/libapp.so  -> Machine: ARM
FLUTTER_APP_RUNTIME_MODES = "release"

inherit flutter-app
