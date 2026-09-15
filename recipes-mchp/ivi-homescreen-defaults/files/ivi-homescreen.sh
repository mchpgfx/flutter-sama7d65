# Defaults for the ivi-homescreen software backend on SAMA7D65 Curiosity.
#
# IVI_SW_SINK is not optional. The software backend's sink defaults to "none",
# which renders every frame and then discards it: a blank display, no error, only
# "[SoftwareBackend] sink: none (frames discarded)" in the log. There is no CLI
# flag for it, and the --drm-* options do not reach the software sink.
export IVI_SW_SINK=drm-dumb

# rgb565 matches the panel's native 16 bpp (U-Boot sets
# video=Unknown-1:800x480-16). Measured noticeably faster on hardware than the
# default 32 bpp: it avoids a 32->16 conversion every frame and halves the
# scanout write bandwidth, which matters because this SoC has no GPU and every
# pixel is written by the CPU.
#
# Trade-off: 16 bpp has coarser colour, so smooth gradients can band. If that is
# visible, try IVI_SW_DRM_DITHER before giving up the speed, or unset this
# variable to go back to 32 bpp.
export IVI_SW_DRM_FORMAT=rgb565

# Only affects login shells. A production launcher (systemd unit, init script)
# must set these itself - profile.d is not read by services.
