SUMMARY = "Demo selector menu (Flutter) for the SAMA7D65 Curiosity"
DESCRIPTION = "Menu screen offering Flutter Gallery or the Material 3 demo. Writes the chosen \
bundle path to /run/demo-choice and exits; flutter-demo-launcher starts the selection. Carries \
the Flutter logo via the built-in FlutterLogo widget, so no asset is shipped."
AUTHOR = "local"
SECTION = "graphics"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://flutter_demo_menu"

S = "${WORKDIR}"
PUBSPEC_APPNAME = "flutter_demo_menu"
FLUTTER_APPLICATION_PATH = "flutter_demo_menu"
FLUTTER_APP_RUNTIME_MODES = "release"

inherit flutter-app
