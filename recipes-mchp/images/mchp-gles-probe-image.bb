DESCRIPTION = "Headless image plus OpenGL ES probes, to measure Mesa software \
rendering (llvmpipe) performance on the 800x480 LVDS panel before committing to \
a Flutter build."
LICENSE = "MIT"

# Deliberately built on the headless image rather than mchp-graphics-image: this
# is a measurement image, and EGT's demo suite would only add build time and
# confuse what is being measured. mchp-graphics-image stays untouched as the
# known-good fallback.
require recipes-mchp/images/mchp-headless-image.bb

# All three run headless straight on DRM/KMS - no X server, no compositor:
#   glmark2      -> glmark2-es2-drm; prints GL_VENDOR/GL_RENDERER/GL_VERSION and
#                   then a score. This is the number that decides Stage 2, and it
#                   also confirms llvmpipe is really the renderer.
#   kmscube      -> minimal GBM + EGL + GLES2 smoke test. This is the specific
#                   probe for kms_swrast working on a dumb-buffer-only DRM device,
#                   which is the least-travelled part of the Mesa path here.
#   libdrm-tests -> modetest, to confirm the 800x480 LVDS mode is present and set.
#
# mesa-demos is intentionally NOT installed: it has
# REQUIRED_DISTRO_FEATURES = "opengl x11" and its binaries (es2gears, eglinfo)
# are X11-bound, so they cannot run here.
IMAGE_INSTALL:append = "\
    glmark2 \
    kmscube \
    libdrm-tests \
"
