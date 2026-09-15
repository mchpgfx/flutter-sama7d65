# Flutter on the Microchip SAMA7D65 Curiosity — Yocto workspace

A Yocto/OpenEmbedded workspace that builds Microchip's `meta-mchp` BSP for the **SAMA7D65
Curiosity** board, and runs **Flutter** on it through a pure-CPU rendering path.

Two images are useful here:

| Image | Contents |
|---|---|
| `mchp-graphics-image` | Microchip's stock EGT image. Known-good fallback. |
| `mchp-flutter-bench-image` | Flutter (ivi-homescreen software backend) + 25 benchmark/demo apps. |
| `mchp-gles-probe-image` | Mesa software-GLES probes (`glmark2`, `kmscube`). Historical baseline. |

## The hardware constraint that shapes everything

| | |
|---|---|
| CPU | **Single-core** Cortex-A7 @ 1 GHz |
| RAM | 1 GB (`cma=192m` reserved for display) |
| GPU | Vivante GC, **2D only — no OpenGL ES** |
| Display | 800×480 LVDS (ST7262) @ 53 Hz, **16 bpp** |
| Touch | Atmel maXTouch |

There is no 3D GPU, so **all rendering is done on the CPU**. Everything below follows from
that.

## Status

Working on hardware: Flutter 3.47.4 engine (armv7, **AOT**, LTO), `ivi-homescreen` 3.0
software backend rendering Skia CPU output straight into a DRM dumb buffer, touch and keyboard
input, text, and 25 apps installed including a scene-based render benchmark.

**Performance is measured.** A conventional instrument/HMI UI — text, vector gauges, lists,
value readouts, 1:1 images — runs at the display's refresh ceiling. Image scaling, gradients,
shadows, blur and stacked translucency are 4–10× over budget and must be designed out. See
[GUI design constraints](#gui-design-constraints-measured).

## Quick start

### 1. Host prerequisites (Ubuntu 24.04)

```bash
sudo apt-get install -y gawk wget git-core git-lfs diffstat unzip texinfo gcc-multilib \
  build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
  debianutils iputils-ping python3-git python3-jinja2 libegl1 libsdl1.2-compat-dev \
  pylint xterm zstd liblz4-tool file locales libacl1
```

Microchip's own package list is stale on 24.04: `pylint3`→`pylint`,
`libegl1-mesa`→`libegl1`, `libsdl1.2-dev`→`libsdl1.2-compat-dev`.

**AppArmor blocks BitBake** on 24.04. Grant `userns` to the BitBake binary only, rather than
disabling the protection system-wide — create `/etc/apparmor.d/bitbake`:

```
abi <abi/4.0>,
include <tunables/global>
profile bitbake /ABSOLUTE/PATH/TO/bitbake/bin/bitbake flags=(unconfined) {
  userns,
  include if exists <local/bitbake>
}
```

then `sudo apparmor_parser -r /etc/apparmor.d/bitbake`. **The path is hardcoded — regenerate
it if this workspace moves.**

### 2. Fetch the workspace

```bash
mkdir -p ~/bin && curl -sSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo
chmod a+x ~/bin/repo && export PATH="$HOME/bin:$PATH"

mkdir yocto && cd yocto
git clone ssh://git@bitbucket.microchip.com/mg/flutter.git meta-local
./meta-local/setup-workspace.sh
```

`setup-workspace.sh` runs `repo init`/`repo sync` for the Microchip BSP at tag
`linux4microchip-2026.04`, then clones the two layers that are **not** in that manifest —
`meta-clang` and `meta-flutter` — at **pinned commits** rather than branch tips:

| Layer | Pinned revision |
|---|---|
| `meta-clang` | `cc29beb210ab94eacc53bbd67e287e4e33ede342` (scarthgap) |
| `meta-flutter` | `719826d2f71076fb616ffea59ee413ad3c62ccba` (scarthgap) |

Pinning matters: following the branch would silently change the Flutter engine version, and
with it every app bundle. Both live outside the manifest so `repo sync` cannot revert them.

### 3. Configure

```bash
export TEMPLATECONF=../meta-local/conf/templates/default
source openembedded-core/oe-init-build-env build     # never pipe this
```

That is the whole configuration step. The template in this layer seeds
`build/conf/local.conf` and `build/conf/bblayers.conf` with every setting described in
[Build configuration](#build-configuration) and the full layer list — including
`meta-flutter-apps`, which is a **separate layer** inside the meta-flutter checkout and
easily missed (without it, its ~220 third-party app recipes are invisible and every target
fails with `Nothing PROVIDES`).

`TEMPLATECONF` is read **only** when `oe-init-build-env` first creates a build directory. To
pick up template changes later, either point it at a fresh directory or copy the samples over
`build/conf/` by hand.

`TMPDIR`, `SSTATE_DIR` and `DL_DIR` are `?=` and default to inside `build/`. A Flutter build
wants **80–120 GB** there; override them in your own `build/conf/local.conf` if that partition
is small. Note oe-core appends `-glibc`, so `TMPDIR` becomes `tmp-glibc` on disk.

### 4. Build and flash

```bash
bitbake mchp-flutter-bench-image
```

Images land in `$TMPDIR-glibc/deploy/images/sama7d65-curiosity-sd/`. Note oe-core appends
`-glibc` to `TMPDIR`.

```bash
# Unmount as a SEPARATE command: a failed umount inside a && chain silently skips the write
udisksctl unmount -b /dev/mmcblk0p1 ; udisksctl unmount -b /dev/mmcblk0p2
sudo dd if=<image>.wic of=/dev/mmcblk0 bs=4M conv=fsync status=progress && sync
```

Check the target with `lsblk` first. On a desktop session `pkexec` works where `sudo` cannot
prompt.

## Running Flutter apps on the board

```sh
homescreen -b /usr/share/flutter/<app>/3.47.4/release
ls /usr/share/flutter/        # what is installed
```

`IVI_SW_SINK=drm-dumb` and `IVI_SW_DRM_FORMAT=rgb565` are exported by
`/etc/profile.d/ivi-homescreen.sh` (the `ivi-homescreen-defaults` recipe), so no environment
setup is needed in a login shell. **A systemd launcher must set them itself** — services do
not read `profile.d`.

**`IVI_SW_SINK` is mandatory.** Without it the software backend defaults to `none` and
silently discards every frame — a blank display with no error, only
`[SoftwareBackend] sink: none (frames discarded)` in the log. There is **no CLI flag** for it
and `--help` does not mention it; the `--drm-*` options do *not* reach the software sink.

Valid sinks: `none | memory | file:<pattern> | fbdev[:<dev>] | drm-dumb[:<dev>] |
encoder:file:<path>` — it is `drm-dumb`, **not** `drm`. Success prints
`[SoftwareBackend] sink: drm-dumb (device='...', 800x480@53.00Hz)`.

Useful extras: `IVI_SW_STOP_AFTER_FRAMES` (render N frames then exit — good for scripted
measurement), `IVI_SW_PROFILE`, `IVI_SW_DRM_FORMAT` (e.g. `rgb565` to match the 16 bpp panel),
`IVI_SW_VSYNC`. `homescreen --drm-list-modes` enumerates connectors and exits.

If the sink reports `failed to initialize` (as opposed to `none`), add `--drm-no-seat` — needed
on a serial console or over SSH, where libseat finds no session.

## Why CPU rendering, and what was ruled out

**Software OpenGL ES was measured and rejected.** Mesa 24.0.7 comes up correctly on this board
(EGL 1.5, GLES 3.2, `kms_swrast`, 800×480 surface) and `llvmpipe (LLVM 18.1.8, 128 bits)`
confirms NEON is active. But:

- **llvmpipe segfaults** the moment rasterisation starts — LLVM JIT codegen on armv7.
  `GALLIUM_DRIVER=softpipe` works, isolating the fault to the JIT rather than KMS or buffers.
- **softpipe scores `glmark2 Score: 1`** — 5 fps trivial geometry, 3 fps textured, 1 fps for
  blur/convolution, 75 s/frame for `[terrain]`.

Do not repeat this experiment expecting a different result.

**The chosen path instead:** `ivi-homescreen` v3.0's `software` backend with
`software-sink-drm`, so Skia's CPU rasteriser (mature 2D code with NEON paths) writes directly
into a DRM dumb buffer. This deletes the entire software-GL emulation layer, so the glmark2
figures above do **not** bound it.

Note meta-flutter's README claims no OSS embedder supports software rendering. **That README
is out of date** — its CHANGELOG is authoritative.

## Build configuration

These are **already applied** by `conf/templates/default/local.conf.sample` — the list below
is the rationale, not a checklist to type in. Edit the sample and re-seed (or copy it over
`build/conf/`) to change them for everyone; edit `build/conf/local.conf` for a local-only
tweak.

Key settings, all with reasons:

```
DISTRO_FEATURES:append = " opengl"      # ONLY because flutter-engine has
                                        # REQUIRED_DISTRO_FEATURES = "opengl".
                                        # It depends on no GL implementation.

PACKAGECONFIG:pn-flutter-engine = "release backtrace embedder-for-target fontconfig \
                                   fstack-protector dart-dynamic-modules dart-secure-socket"
# The recipe default is "debug profile release" = THREE complete engine builds.
# Never add 'slimpeller': it strips Skia, which is what software rendering uses.

PACKAGECONFIG:pn-ivi-homescreen = "backend-software software-sink-drm \
                                   software-input-libinput lto disable-plugins"
# Stock default is backend-wayland-egl plus app plugins.
# 'hud' is omitted: it requires 'compositor', draws every frame (skewing the numbers
# it reports) and changes the presentation path.

FLUTTER_APP_SUPPORTED_ARCHS = "x64 arm64 riscv64 arm"
FLUTTER_BUILD_ARGS:remove = "--target-platform linux-arm"
# See "Flutter apps on 32-bit ARM" below.

BB_NUMBER_THREADS = "4"                 # memory-bound, not core-bound: 20 cores but
PARALLEL_MAKE = "-j6"                   # 31 GB shared with a desktop and only 8 GB swap
BB_PRESSURE_MAX_MEMORY = "5000"
BB_PRESSURE_MAX_IO = "10000"
```

### Flutter apps on 32-bit ARM

meta-flutter skips **every** app recipe on armv7:

```
flutter build bundle has no linux-arm target platform;
Flutter supports only x64, arm64, riscv64 for Linux app bundles
```

The message is accurate but the conclusion is too strong. Reading
`meta-flutter/conf/include/common.inc`'s `do_compile`:

1. `flutter build bundle` produces `flutter_assets` + `kernel_blob.bin` — Dart kernel
   bytecode, **architecture-independent**.
2. For `release`/`profile` the recipe *then* unzips `engine_sdk.zip` from the
   **engine built for armv7** and runs its own
   `gen_snapshot --snapshot_kind=app-aot-elf --elf=libapp.so`.

AOT never came from `flutter build bundle`, so dropping the rejected argument (the two lines
above) is sufficient. **Verify the result** — `readelf -h` on the packaged `libapp.so` must
report `Machine: ARM`. A build that succeeds while emitting host x86-64 code would be a false
pass.

Fallback would be `jit_release` (arch-independent `kernel_blob.bin`), but note meta-flutter's
JIT path has never been executed: `common.inc` line 521 calls
`run_command(cmd, source_root, env)`, omitting the leading `d` that all other call sites pass.

## What is in this layer

`meta-local` is the only version-controlled part of the workspace, and it holds everything
local: configuration, overrides, the benchmark app and these docs. Everything else is fetched
by `setup-workspace.sh` — the `repo`-managed layers are pinned by manifest tag, and
`meta-clang`/`meta-flutter` by explicit commit.

**All overrides live here deliberately.** Edits to `openembedded-core` or `meta-mchp` are
reverted by `repo sync`, so anything patched there would silently disappear.

| Path | Purpose |
|---|---|
| `conf/templates/default/` | `TEMPLATECONF` template: `local.conf.sample`, `bblayers.conf.sample`, `conf-notes.txt`. Reproduces the entire build configuration and layer list. |
| `setup-workspace.sh` | Fetches the BSP via `repo`; clones `meta-clang` and `meta-flutter` at pinned commits. |
| `recipes-devtools/pseudo/pseudo_git.bbappend` | **Load-bearing — do not remove.** Pins pseudo 1.9.11. Scarthgap's 1.9.0 has no `openat2()` wrapper, so on a modern host (glibc 2.39 / tar 1.35 / kernel 7.x) **every** `do_package` fails with `got *at() syscall for unknown directory`. |
| `recipes-graphics/toyota/ivi-homescreen_3.0.bbappend` | Adds `virtual/libgles2`. A software-only build still needs GLES *headers* to compile, because `flutter_desktop_texture_registrar.h` includes `<GLES2/gl2.h>` unconditionally. Headers only — nothing links GL. |
| `recipes-flutter-apps/apps/*_%.bbappend` | Sets `S = "${WORKDIR}/git"` for 13 third-party apps. 174 of 220 meta-flutter-apps recipes omit `S`, assuming newer oe-core aligns the git fetcher with `${WORKDIR}/${BP}`. Scarthgap unpacks to `${WORKDIR}/git`. |
| `recipes-flutter/flutter-hmi-bench/` | The scene-based render benchmark (recipe + Dart source). Produces the constraints table below. |
| `recipes-mchp/cpufreq-performance/` | systemd unit pinning the CPU governor. The board ships `conservative`, idling at 90 MHz of an available 1000 MHz. With no GPU, clock speed *is* frame rate. |
| `recipes-mchp/ivi-homescreen-defaults/` | `/etc/profile.d/ivi-homescreen.sh` exporting `IVI_SW_SINK=drm-dumb` (mandatory) and `IVI_SW_DRM_FORMAT=rgb565` (measured faster). |
| `recipes-mchp/images/` | `mchp-flutter-bench-image`, `mchp-gles-probe-image`. |

`BB_GIT_DEFAULT_DESTSUFFIX` would fix the `S` problem globally but is **deliberately not
used**: it changes the unpack destination for every git recipe, breaking the many that set
`S = "${WORKDIR}/git"` on purpose (pseudo, ivi-homescreen, dt-overlay-mchp).

### Not tracked, and why

- The `repo`-managed layers — pinned by manifest tag instead.
- Build output (`build/`) — regenerable, and tens of GB.
- `/etc/apparmor.d/bitbake` — host-local, and it hardcodes an absolute path to the BitBake
  binary, so each developer generates their own (see [Quick start](#quick-start)).

## Troubleshooting

The failures in this stack tend to be silent. Symptom → cause:

| Symptom | Cause |
|---|---|
| **Blank display**, log says `sink: none (frames discarded)` | `IVI_SW_SINK` not set. It defaults to discarding frames. |
| **No text at all**, but shapes/icons render | **No fonts installed.** Flutter's default text font comes from the system via fontconfig; icons come from bundled `MaterialIcons`. Check `fc-list \| wc -l` and `fc-match sans`. |
| Wrong resolution (1920×720) | Symptom of no sink — with one, the backend adopts the panel's native mode. |
| Keyboard dead, `failed to add default include path /usr/share/X11/xkb` | `xkeyboard-config` missing. |
| `sink: drm-dumb ... failed to initialize` | libseat has no session (serial console / SSH). Add `--drm-no-seat`. |
| Every `do_package` fails, `unknown base path for fd` | pseudo too old — see `meta-local`. |
| "User namespaces are not usable by BitBake" | AppArmor — see host prerequisites. |
| `Nothing PROVIDES` but the `.bb` exists | Recipe is being **skipped** at parse, or its layer isn't added. `bitbake -e <recipe> \| grep -i skip`. |
| App fails: `.flutter-plugins-dependencies lists Linux plugins (...)` | The app needs a Linux plugin; incompatible with `disable-plugins`. Definitive, not a workaround candidate. |
| Build killed, no `^ERROR` in log | OOM. Lower parallelism. sstate survives — just re-run to resume. |
| `bitbake-getvar` hangs | A build holds the server lock. |
| `MESA-LOADER: failed to open atmel-hlcdc`, `Failed to restore original CRTC: -2` | **Benign.** Expected fallback and exit noise. |

Two habits that save time here: require BitBake's own `rc=0` **and** zero `^ERROR` lines (a
wrapper script exiting 0 around a failed build has caused a false "success"), and verify the
*artefact* rather than the exit status — `readelf -h` for target architecture, `readelf -d` for
unwanted runtime linkage, the image manifest for packages that were the point.

Also: task counts are not duration. One task can be an entire LLVM or Flutter-engine build.

## Known limitations

- **Plugins do not work.** `disable-plugins` is required — the plugin tree fails against the
  software backend (`undeclared identifier 'FlutterDesktopGetPluginRegistrar'`; the v3.0
  embedder builds against the plugins v2.0 branch, evidently only exercised with EGL
  backends). **Consequence for a product:** platform integration cannot go through plugins.
  Prefer **`dart:ffi`** (call C libraries directly from Dart — often cleaner and faster than a
  platform channel) or a separate native daemon over a socket with `dart:io`.
- Apps needing Linux plugins therefore cannot be built: `flutter-samples-provider-shopper` and
  `flutter-samples-simplistic-calculator` both require `window_size`.
- **No chart/graph app** exists among meta-flutter's 220 third-party recipes. Plots need a
  custom app; `fl_chart` and `syncfusion_flutter_charts` are pure Dart and work plugin-less.
- `isolate_snapshot_data` is ~12 MB per app and unused in AOT mode — roughly 250 MB of the
  942 MB image is dead weight, trimmable if size matters.
- Fragment-shader samples (`simple-shader`, `simple-sdf`) need Impeller/GPU and will not work.

## Performance: what has been measured

Subjective read of the stock demo apps on hardware: **usable, but not smooth.** Scaling and
alpha blending with images are clearly sluggish. That is the expected profile — both are
fill-rate bound, and on a CPU rasteriser cost tracks pixels touched.

**Two configuration changes measurably helped, and both are now defaults in the image:**

| Change | Why it matters |
|---|---|
| **CPU governor → `performance`** | The board ships `conservative`, idling at **90 MHz of an available 1000 MHz** and ramping in small steps. With no GPU, clock speed *is* frame rate, and bursty UI work is what `conservative` handles worst. Pinned at boot by `cpufreq-performance`. |
| **Framebuffer → `rgb565`** | The panel is natively 16 bpp. A 32 bpp target costs a conversion every frame and double the scanout writes. Set by `ivi-homescreen-defaults`. |

Engine `lto` is also enabled, but expect much less from it: it tightens the code that touches
each pixel without reducing how many pixels are touched.

**Caveat on earlier figures.** Everything measured before the governor was changed — including
the `glmark2 Score: 1` that ruled out software OpenGL ES — was taken with `conservative`
active, so those numbers are pessimistic by an unknown factor. The GLES conclusion very likely
still stands (even an order of magnitude would leave it unusable, and llvmpipe segfaults
regardless), but the figures should be read as a floor rather than a limit. Check clock state
before treating any number on this class of board as a hardware limit.

## GUI design constraints (measured)

Measured 2026-09-15 with `flutter-hmi-bench` on hardware at 1 GHz / 16 bpp: 23 scenes, 20
warm-up plus 90 measured frames each, timings from `SchedulerBinding.addTimingsCallback`.
Budget: **30 fps = 33 ms/frame**.

**Everything is raster-bound.** `buildDuration` was 2.5–12 ms in every scene, so the UI
thread is never the constraint — only pixels are.

### The ~18.6 ms floor — read the table with this in mind

Every cheap scene reported `raster_med` of 18.1–18.9 ms regardless of content, from bare text
to a full-screen fill. **The panel runs 53 Hz = 18.87 ms per refresh**, so those scenes are
**display-bound, not CPU-bound**: their true content cost is hidden beneath a vsync wait or a
fixed full-screen present cost. Anything at the floor has unknown (but positive) headroom;
anything well above it is genuinely work-bound.

### Constraints table

| Technique | raster med (ms) | Verdict |
|---|---|---|
| Static text, gauge face, arc/ticks, large digits | 18.6–18.8 | ✅ at floor |
| Animated needle, with **or** without `RepaintBoundary` | 18.7–18.8 | ✅ at floor |
| List scroll — plain text, and icons + dividers | 14.4–17.5 | ✅ at floor |
| Switches, progress bars, periodic value updates | 18.1–18.8 | ✅ at floor |
| Image drawn **1:1**, `FilterQuality.none` | 18.6 | ✅ at floor |
| Opacity animation (`saveLayer`) over sparse text | 18.6 | ✅ but see caveat |
| Antialiased `ClipRRect` (×6) | 21.0 (p95 34.1) | ⚠️ marginal |
| Waveform / line chart, 3 × 267-point polylines | 78–80 | ❌ 6.6 fps |
| `BoxShadow` / Material elevation (×8) | 79.6 | ❌ 6.7 fps |
| Image scaled 1.7×, `FilterQuality.low` | 131.2 | ❌ 3.9 fps |
| **Full-screen linear gradient** | 141.6 | ❌ 3.6 fps |
| `BackdropFilter` blur | 154.9 | ❌ 3.3 fps |
| Stacked translucent layers (×6) | 189.3 | ❌ 2.7 fps |
| Image scaled 1.7×, `FilterQuality.medium` | 190.5 | ❌ 2.7 fps |

**The cliff is ~4×, not gradual.** Techniques sit either at the floor or 4–10× over budget,
with almost nothing in between — so design decisions here are binary rather than a matter of
tuning.

### Design rules

1. **Never scale images at runtime.** 1:1 is free; 1.7× costs 7×, and `FilterQuality.medium`
   costs 10×. Pre-size every asset to its exact on-screen pixel size; cap decode with
   `cacheWidth`/`cacheHeight`; use `FilterQuality.none` or `.low`.
2. **No full-screen gradients.** One `ui.Gradient.linear` across 800×480 costs 141 ms. Use
   flat fills, or a small pre-rendered gradient bitmap drawn 1:1.
3. **No stacked translucency.** Six semi-transparent rectangles cost 189 ms. Composite opacity
   into flat opaque colours at design time.
4. **No shadows, no blur.** `BoxShadow` 80 ms, `BackdropFilter` 155 ms. Use borders, rules or
   flat colour steps for depth.
5. **Charts need an explicit budget.** 80 ms for 3 × 267 points. Decimate to at most one point
   per horizontal pixel, cache static grid/axes behind a `RepaintBoundary`, and prefer
   1 px non-antialiased strokes.
6. **Everything a conventional instrument UI needs is affordable**: text, large digits, vector
   gauges and needles, lists, switches, progress bars, periodic value updates, and 1:1 images.

### Caveats on these figures

- **The `RepaintBoundary` comparison measured nothing.** With/without came out 18.7 vs 18.8
  because both were clamped at the floor. The benefit is real but only visible once a scene
  exceeds the floor — re-test by wrapping something expensive (a chart), not a cheap needle.
- **The `saveLayer` pass is weak evidence.** That scene wraps sparse text, so the offscreen
  layer covers little. `BackdropFilter` (155 ms) and antialiased clips (21 ms) also use
  `saveLayer` and cost more, so treat opacity animation over a large or busy subtree as
  expensive despite this result.

## Open questions

**Is the 18.6 ms floor a vsync wait or a fixed present cost?** This decides how much of the
33 ms budget is actually available for content. One run settles it:

```sh
IVI_SW_VSYNC=0 homescreen -b /usr/share/flutter/flutter_hmi_bench/3.47.4/release
```

If the cheap scenes fall well below 18.6 ms raster, it was vsync and real headroom exists.
If they hold at ~18.6 ms, it is a hard floor — a full-screen blit plus 32→16 conversion into
the dumb buffer — which would cap the display near 50 fps with no content at all, and mean
roughly 14 ms of the 33 ms budget is left for drawing.

## Reference

- BSP: <https://github.com/linux4microchip/meta-mchp> (tag `linux4microchip-2026.04`,
  scarthgap / yocto-5.0.15)
- Manifests: <https://github.com/linux4microchip/meta-mchp-manifest>
- meta-flutter: <https://github.com/meta-flutter/meta-flutter> (branch `scarthgap`)
- meta-clang: <https://github.com/kraj/meta-clang> (branch `scarthgap`)
- ivi-homescreen: <https://github.com/toyota-connected/ivi-homescreen> (branch `v3.0`)

The display needs no work: the board DTS has no display nodes, and U-Boot auto-detects the
panel — on an ST7262 it selects the `lvds` overlay from `sama7d65_curiosity.itb` and appends
`video=Unknown-1:800x480-16` to bootargs, with timings carried in the overlay and driven by
`CONFIG_DRM_PANEL_LVDS`. Leave `dt-overlay-mchp`, `bootargs` and `bootcmd` alone.

`CLAUDE.md` in this directory holds the same operational knowledge in a terser form, aimed at
AI coding agents rather than people.
