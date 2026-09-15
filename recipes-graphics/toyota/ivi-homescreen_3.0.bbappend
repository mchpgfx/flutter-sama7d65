# Software-only ivi-homescreen still needs the GLES2 headers at compile time.
#
# shell/platform/homescreen/flutter_desktop_texture_registrar.h opens with an
# unconditional `#include <GLES2/gl2.h>`, and platform_homescreen is compiled for
# every backend, so a backend-software build fails with:
#
#   fatal error: 'GLES2/gl2.h' file not found
#
# In ivi-homescreen-v3.inc, virtual/libgles2 is attached only to the EGL backends
# (backend-wayland-egl, backend-drm-kms-egl, backend-headless-egl), so a
# software-only PACKAGECONFIG never stages those headers.
#
# This is an upstream oversight rather than a real dependency: the header's
# GL_TEXTURE_2D_DESC struct declares its fields as plain uint32_t and the header
# calls no GL functions, so the include is unused. Upstream could simply drop it,
# or guard it behind the EGL backends.
#
# Supplying the headers is the least invasive fix - no patch to upstream sources,
# and it also covers any sibling file in the same CMake target that does want GL
# declarations. It costs nothing at runtime: with no EGL backend enabled, CMake
# adds no GL libraries to the link, so the binary gains no libGLESv2 dependency.
# mesa PROVIDES virtual/libgles2 here (PACKAGECONFIG keeps 'gles'), so this needs
# no new component built.
#
# If the link ever does start pulling libGLESv2 in, prefer patching the include
# out over enabling an EGL backend - the point of this configuration is that no
# GL implementation is used at runtime.
DEPENDS += "virtual/libgles2"
