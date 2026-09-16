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
| Display | 800×480 LVDS (ST7262) @ **52.64 Hz** (19.0 ms/refresh), **16 bpp** |
| Touch | Atmel maXTouch |

There is no 3D GPU, so **all rendering is done on the CPU**. Everything below follows from
that.

## Status

Working on hardware: Flutter 3.47.4 engine (armv7, **AOT**, LTO), `ivi-homescreen` 3.0
software backend rendering Skia CPU output straight into a DRM dumb buffer, touch and keyboard
input, text, and 25 apps installed including a scene-based render benchmark.

**Performance is measured.** The per-frame budget is **19.0 ms** (one 52.64 Hz refresh), and
frame rate steps rather than degrades — 52.6 / 26.3 / 17.5 fps. A conventional instrument UI
(text, large digits, value readouts, progress bars, lists, 1:1 images, `RepaintBoundary`-bounded
gauges) costs 6–12 ms and has real headroom. Runtime image scaling, gradients, shadows, blur and
stacked translucency are 2–15× over and must be designed out. See
[GUI design constraints](#gui-design-constraints-measured).

**Shipped to a customer pilot.** Two field findings are folded into
[Troubleshooting](#troubleshooting): pin `--drm-connector` explicitly, and never ship
`IVI_SW_VSYNC=0`.

**`mchp-flutter-gallery-image` boots straight to a demo menu** (Flutter Gallery or the
Material 3 demo; the USER button on PC10 returns to the menu). It is **panel-size
agnostic** — see [One image, any panel size](#one-image-any-panel-size).

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

## The 2D GPU (libm2d) — enabled, not yet used by Flutter

The SoC has a **Vivante GC520UL 2D core**. It ships unusable: `sama7d65.dtsi` describes
`gpu@e1480000` fully (reg, IRQ, bus/core clocks, 533 MHz GPU PLL) but leaves it
`status = "disabled"`, and **no board DTS or overlay in the tree references `&gpu`**. The
GFX2D node on sam9x7 is disabled the same way, so this is an opt-in-per-board convention.
A consequence worth knowing: **EGT is not using the GPU either**, despite
`packagegroup-mchp-graphics` already installing `libm2d` on this machine.

`meta-local/recipes-kernel/linux/linux-mchp_6.18.bbappend` enables it with a DTS patch
(`&gpu { status = "okay"; }`, scoped `:sama7d65`). A kernel patch rather than an overlay
because the overlays here are packed into `sama7d65_curiosity.itb` and chosen by U-Boot's
panel-detection logic — adding one would mean editing `dt-overlay-mchp`'s `.its` *and* the
boot-time selection, for a block that is always present and has no board variation.

**Verified on hardware** with `mchp-m2d-probe-image` (2026-09-16):

```
nano2d irq number is 194.
create /dev/nano2d device.
  register base:0xe1480000        <- matches the DTS node
```

`m2d_test` (from `libm2d`, assets in `/usr/share/m2d/` including 800×480 ones) renders
visible output on the panel. The out-of-tree nano2D module 2.0.41 probes fine against kernel
6.18.17.

The stack, all pre-packaged in meta-mchp: `kernel-module-nano2d` (autoloads) + **`libnano2d2`**
(the runtime package is *not* called `nano2d`) + `libm2d` 2.2.1 + `libplanes`.

### What it can and cannot do

From `include/m2d/m2d.h`: blit and fill (`m2d_draw_rectangles`), **stretched/scaled blit**,
programmable blending (GL-like functions and factors), up to 8 sources per pass, lines,
ARGB8888/RGB565/A8, dma-buf `m2d_import`, and **explicit** `m2d_sync_for_cpu`/`_for_gpu` cache
management.

There is **no path rasteriser, no text, no gradient op, no convolution and no antialiasing**.
So it cannot touch the chart (80 ms), blur (155 ms) or live-gradient (141 ms) costs in the
constraints table. It addresses image scaling, alpha compositing, fills and format conversion.

### Why it is not used — measured, and settled

The only operation the GPU could take over is the ARGB8888→RGB565 present blit, and **that
costs roughly 2–4 ms** — see [Why the 2D GPU is not used](#why-the-2d-gpu-is-not-used-despite-being-enabled)
for the derivation. Three reasons it is not worth building:

- Flutter's software renderer hands the embedder *engine-owned* memory
  (`surface_present_callback`) which can only be copied out of. Zero-copy needs the
  **compositor API** with embedder-allocated `m2d_alloc` backing stores — a patch against a
  third-party embedder we would then maintain.
- Flutter hands a compositor **one** backing-store layer unless platform views are in use, so
  Skia composites the whole widget tree — every alpha blend, every scaled image — in software
  before the compositor sees anything. Only the present path is reachable.
- Explicit cache maintenance on a non-coherent GPU (`m2d_sync_for_cpu`/`_for_gpu`) flushing
  ~1.5 MB per frame could plausibly cost what the swizzle costs.

None of it touches the flip wait, which is the larger part of the per-frame floor and is the
display pacing the renderer, not work.

## One image, any panel size

Nothing in the rootfs is tied to 800x480. The resolution comes from the mode the kernel
sets, and every layer above it follows:

| Layer | How it learns the size |
|---|---|
| `atmel-hlcdc` XLCDC | Panel timings from the DT overlay. Controller limit is **2048x2048** (`atmel_hlcdc_dc.c`, `atmel_xlcdc_dc_sama7d65`), so 1280x800 is well inside it |
| `ivi-homescreen` software sink | Adopts the connector's current mode; `-w`/`--height` are unnecessary |
| Flutter engine | Told the view size by the embedder |
| Demo apps + menu | Lay out from `MediaQuery` / `View.of(context)` |

**Switching panels is a bootargs/overlay change, not an image change.** U-Boot detects the
panel and selects the overlay that carries its timings; on the fitted ST7262 it appends
`video=Unknown-1:800x480-16`. Point it at a different panel and the whole stack follows.

**The menu reports what it actually found**, so the panel is self-evident on screen:

```
Skia CPU · 1280x800 @ 60.0 Hz · NEON+VFPv4 · no GPU
```

Resolution and refresh rate come from `View.of(context).physicalSize` and
`Display.refreshRate`; the SIMD field is parsed from `/proc/cpuinfo` `Features`. An earlier
version hardcoded the string `800x480`, which would have gone on claiming 800x480 on a
1280x800 panel — a display readout that cannot be wrong is worth the ten lines.

`test/menu_layout_test.dart` asserts no overflow at 480x272, 800x480, 1024x600, 1280x800,
2048x2048 and two portrait sizes. Run it on the host:

```sh
SDK=$(dirname $(find ~/yocto-build/tmp-glibc -path '*/flutter/sdk/bin/flutter' | head -1))
cd meta-local/recipes-flutter/flutter-demo-menu/files/flutter_demo_menu
PATH="$SDK:$PATH" PUB_CACHE="$(dirname $SDK)/.pub-cache" flutter pub get --offline
PATH="$SDK:$PATH" PUB_CACHE="$(dirname $SDK)/.pub-cache" flutter test
```

That test earned its keep immediately: the menu stacked its two tiles when *width* was
small, which is backwards — stacking doubles the height needed, so a short landscape panel
(480x272) overflowed. It now stacks only when the panel is portrait.

### The cost, which does not scale for free

**A bigger panel is proportionally more work for the CPU**, because the CPU draws every
pixel. 1280x800 is **2.67x** the pixels of 800x480, and fill-rate-bound work scales with
that ratio while the per-refresh budget does not:

| Scene (measured at 800x480) | 800x480 (19.0 ms budget) | Projected at 1280x800 (18.4 ms budget) |
|---|---|---|
| Full-screen fill | 8.8 ms | ~23 ms — **over budget** |
| Progress bars | 6.2 ms | ~17 ms — marginal |
| Big digits | 7.7 ms | ~21 ms — **over** |
| List scroll | 11–15 ms | ~29–40 ms — **well over** |

Those projections are arithmetic on the pixel-count ratio, **not measurements** — text and
path rasterisation scale with glyph and path area rather than screen area, so treat them as
an upper bound and re-run `flutter-hmi-bench` on the actual panel before committing to a
design. The direction is not in doubt, though: **the constraints table in
[GUI design constraints](#gui-design-constraints-measured) is specific to 800x480 and gets
tighter on a larger panel.** Budget headroom is the thing a bigger display spends.

A larger panel also raises the refresh period question again: the budget is one refresh, so
measure the new mode's rate rather than assuming 52.64 Hz or 60 Hz.

### The New Vision 10.1" panel: already in the FIT, but not auto-detected

`sama7d65_curiosity.itb` ships an overlay for it. Read straight out of the built FIT rather
than a datasheet:

| | |
|---|---|
| FIT configuration name | **`lvds_newvision`** (siblings: `lvds`, `mipi`) |
| Resolution | **1280x800** |
| Pixel clock | 65 MHz |
| Blanking | h: sync 32, front 48, back 80 · v: sync 8, front 8, back 16 |
| Panel size | 216 x 135 mm (10.1") |
| Refresh | 65e6 / (1440 x 832) = **~54.2 Hz → an 18.4 ms budget** |
| Touch | included — the overlay carries `atmel,maxtouch` |

So the budget barely moves (19.0 → 18.4 ms) while the pixel count goes up 2.67x. That is the
whole story of this panel change in one line.

**U-Boot will not select it for you.** The env has exactly two detection tests:

```
lvdstest=test -n $display && test $display = ST7262 && setenv display_var 'lvds' && ...
mipitest=test -n $display && test $display = HX8394 && setenv display_var 'mipi' && ...
```

Neither matches the New Vision panel, so `display_var` stays empty, no display overlay is
appended and no `video=` bootarg is set. It has to be selected explicitly — something like:

```sh
setenv video_mode_nvd 'Unknown-1:1280x800-16'
setenv nvdtest 'setenv display_var lvds_newvision; setenv at91_video_bootargs video=${video_mode_nvd}'
setenv at91_display_detect 'run lvdstest; run mipitest; run nvdtest; run at91_prepare_bootargs; run at91_prepare_display_overlay'
saveenv
```

Order matters: `nvdtest` must run before `at91_prepare_bootargs` and
`at91_prepare_display_overlay`, and it unconditionally overrides — so remove it before going
back to the ST7262 panel, or gate it on whatever `$display` reports for this one. **This env
snippet is derived from reading the env file, not tested on hardware.** Confirm with
`modetest -c` (mode should read 1280x800) and the menu's own status line.

### If the new panel lands on a different connector

`flutter-demo-launcher` pins `--drm-connector LVDS-1`, deliberately (LVDS has no hotplug
detect, so every LVDS connector claims to be connected). A panel on another connector needs
that pin changed — no rebuild required:

```sh
systemctl edit flutter-demo-launcher    # [Service] / Environment=DEMO_CONNECTOR=DSI-1
```

`modetest -c` lists connectors with their encoder and CRTC bindings; pick the one with a
**non-zero encoder**, not merely `connected`.

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
| `recipes-flutter/flutter-demo-menu/` | The demo selector shown at boot: recipe, Dart source, and `test/menu_layout_test.dart`. Writes the chosen bundle path to `/run/demo-choice` and exits; reports resolution, refresh rate and NEON live. |
| `recipes-mchp/userbtn-wait/` | Blocks until the USER button (PC10) is pressed, then exits 0. Finds its input device by **capability** (`EVIOCGBIT`, test `KEY_0`), not by name. Exits 2 for "no device" and 3 for a read error so a setup failure cannot be mistaken for a press. |
| `recipes-mchp/flutter-demo-launcher/` | The supervisor and its systemd unit: menu → demo → button → menu, forever. Exports `IVI_SW_SINK`/`IVI_SW_DRM_FORMAT` itself (services do not read `/etc/profile.d`) and pins `--drm-connector`. |
| `recipes-mchp/images/` | `mchp-flutter-gallery-image` (boots to the demo menu), `mchp-flutter-bench-image`, `mchp-gles-probe-image`. |

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
| **Intermittent blank screen on a fielded unit** | The sink picks the *first* connector that is `connected` with ≥1 mode, and **LVDS has no hotplug detect** — every LVDS connector reports `connected` whether a panel is fitted or not. This board exposes LVDS-1 **and** LVDS-2 with identical modes but only **one encoder (44) and one CRTC (43)**; LVDS-2 has encoder `0`. So selection reduces to enumeration order and can bind an undrivable output. **Fix: pass `--drm-connector LVDS-1`** (or whichever connector has a bound encoder — check `modetest -M atmel-hlcdc`). When pinned, the sink fails loudly instead of falling back silently. |
| **Tearing during scroll** | Check `IVI_SW_VSYNC` in the *running* process — `tr '\0' '\n' < /proc/$(pgrep -x homescreen)/environ \| grep ^IVI_`. `IVI_SW_VSYNC=0` is a **measurement tool only** and tears by design; it must never ship. If it is unset, grep the log for `force-clearing flip_pending_`: the sink watchdog force-clears when a flip-completion event is not serviced in time and then submits a flip mid-scanout. That indicates event-loop starvation on the single core under load. |

Two habits that save time here: require BitBake's own `rc=0` **and** zero `^ERROR` lines (a
wrapper script exiting 0 around a failed build has caused a false "success"), and verify the
*artefact* rather than the exit status — `readelf -h` for target architecture, `readelf -d` for
unwanted runtime linkage, the image manifest for packages that were the point.

Also: task counts are not duration. One task can be an entire LLVM or Flutter-engine build.

### The demo launcher: three failure modes worth recognising

**Nothing on screen and no `homescreen` process, but the unit is `enabled`.** Check whether
the unit is *waiting* on something: `systemctl list-jobs`. Do **not** order a unit `After=` or
`Wants=` a `dev-dri-cardN.device` unit — device units exist only for devices udev tags
`TAG+="systemd"`, and this image's `99-systemd.rules` tags `tty`, `block`, `net`, `sound`,
`usb`, `ubi`, `ptp`, `bluetooth`, `udc`, `rfkill` and **nothing in the `drm` subsystem**, so
`dev-dri-card0.device` can never activate. `flutter-demo-launcher` polls for `/dev/dri/card*`
itself.

**The demo runs but the USER button does nothing.** Look at the service cgroup:

```sh
systemctl status flutter-demo-launcher --no-pager     # shows the cgroup tree
```

If `userbtn-wait` is **absent** from the cgroup, the supervisor never started it — it is not a
button problem. The cause here was `HS_PID=$(run_bundle …)`: a backgrounded child inherits the
command substitution's stdout pipe and holds it open, so `$( )` blocks for the demo's entire
lifetime and the next line never runs. Never return a PID through `$( )`; start the child in
the caller's shell and read `$!`.

If `userbtn-wait` **is** running, check what it picked — it logs every candidate device with a
`KEY_0=yes/no` verdict. Confirm the button independently:

```sh
cat /proc/bus/input/devices     # expect N: Name="gpio-keys", B: KEY=800  (bit 11 = KEY_0)
journalctl -u flutter-demo-launcher | grep KeyCallback   # keysym 48 = ASCII '0'
```

Note the button reaches Flutter as a `'0'` keypress too, because evdev delivers to every
reader. Harmless in these demos, but a focused `TextField` in a real HMI would receive a zero.

**A blank screen on some units only.** See the connector note above: pin `--drm-connector`.

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

Measured on hardware at 1 GHz / 16 bpp with `flutter-hmi-bench` (23 scenes, 20 warm-up plus 90
measured frames each, timings from `SchedulerBinding.addTimingsCallback`). Revised 2026-10-07
after establishing what the per-frame floor actually was.

### The budget is 19.0 ms, and frame rate is quantised

The panel runs **52.64 Hz** (25 MHz pixel clock over 933x509 total) = **19.0 ms per refresh**.
`DrmDumbSink::Present()` busy-waits on `flip_pending_` for the previous page flip to retire
before it swizzles, and the sink is double-buffered. So frame rate steps rather than degrades:

| Refreshes per frame | Frame rate |
|---|---|
| 1 | 52.6 fps |
| 2 | 26.3 fps |
| 3 | 17.5 fps |

**A screen needing 20 ms of work does not run at 50 fps - it runs at 26.** Design to fit
**19.0 ms** of build + raster. (An earlier revision of this table used a 33 ms / 30 fps budget;
that was the wrong shape of target for a flip-paced display.)

### Two measurement conditions, and how to read them

`raster_med`, milliseconds. **In situ** is the shipping configuration (`drm-dumb`, vsync off).
**Content only** is `IVI_SW_SINK=none` - frames discarded, so no swizzle and no flip wait.

| Technique | in situ | content only | verdict vs 19.0 ms |
|---|---|---|---|
| Progress bars | 18.7 | **6.2** | ✅ ample headroom |
| Large digits, tabular figures | 18.8 | **7.7** | ✅ |
| Opacity animation (`saveLayer`, sparse subtree) | 18.8 | **7.9** | ✅ |
| Image drawn **1:1**, `FilterQuality.none` | 18.8 | **8.1** | ✅ |
| Full-screen solid fill | 18.8 | **8.8** | ✅ |
| List scroll, icons + dividers | 16.8 | **11.3** | ✅ |
| Switches / checkboxes | 18.9 | **11.6** | ✅ |
| **Animated needle WITH `RepaintBoundary`** | 18.8 | **11.7** | ✅ |
| Periodic text value updates | 18.8 | **8.4** | ✅ |
| List scroll, plain text | 16.1 | **15.0** | ✅ marginal |
| Static gauge face (`CustomPaint`) | 18.8 | 20.5 | ⚠️ just over |
| **Animated needle WITHOUT `RepaintBoundary`** | 18.8 | **21.2** | ⚠️ 1.8x the bounded version |
| Arc + tick vector drawing | 18.8 | 31.6 | ❌ |
| `BoxShadow` / Material elevation (x8) | 45.3 | 43.1 | ❌ |
| Antialiased `ClipRRect` (x6) | 18.9 | 49.7 | ❌ in situ OK, see note |
| Image scaled 1.7x, `FilterQuality.low` | 69.9 | 71.6 | ❌ |
| Image scaled 1.7x, `FilterQuality.medium` | 100.8 | 102.5 | ❌ |
| Waveform / line chart, 3 x 267 points | 46.3 | 140.7 | ❌ |
| `BackdropFilter` blur | 83.7 | 179.7 | ❌ |
| Full-screen linear gradient | 76.1 | 255.7 | ❌ |
| Stacked translucent layers (x6) | 99.8 | 279.6 | ❌ |

**Read the two columns differently.** For scenes under one refresh, *in situ* is dominated by
the flip wait and hides the real cost - the content column is the truth and shows genuine
headroom. For scenes over one refresh, the reverse: removing pacing also removes the idle gaps
between frames, so both threads contend on the single core and the content column **inflates**
(charts 141 ms with `none` versus 46 ms in situ). Use *in situ* for those.

`clip_rrect_antialiased` shows this most starkly - 18.9 ms in situ, 49.7 ms unpaced. Treat it
as workable in the shipping configuration but with no headroom.

`baseline.static_text` reported 49.0 ms content-only, wildly out of line with every comparable
scene. It runs first; treat it as a warm-up artefact, not data.

### Design rules

See [Optimisation guidelines](#optimisation-guidelines) below for the consolidated list, ordered
by measured value.

### Why the 2D GPU is not used, despite being enabled

The swizzle the GPU could take over costs roughly **2-4 ms** - derived from the consistent
10-12.5 ms gap between in-situ and content-only on five unrelated cheap scenes, most of which
must be the flip wait. Offloading it would require the Flutter compositor API, embedder-
allocated `m2d_alloc` backing stores, and explicit cache maintenance flushing ~1.5 MB per frame
on a non-coherent GPU - plausibly costing as much as it saves - while not touching the flip
wait at all. The existing path is well matched to the hardware: a NEON `vld4_u8`/`vst4_u8`
swizzle streaming into a write-combining dumb buffer.

Evidence for that last point: `IVI_SW_SINK=memory`, which writes to ordinary cacheable heap,
was **slower than the display path** (charts 46 -> 151 ms) with `buildDuration` rising too.

If offloading is ever revisited, the **display controller's two overlay planes** (with `alpha`
and `rotation`, plus YUV on plane 39) are the better target - hardware compositing at scanout,
no GPU, no libm2d, no cache maintenance, no patched embedder.

## Optimisation guidelines

Ordered by measured or expected value. Everything in Tier 1 is under your control in Dart and
needs no change to the stack.

### The one number to design against

**19.0 ms of build + raster per frame.** The panel is 52.64 Hz and the sink waits for the
previous page flip, so frame rate steps — 52.6 / 26.3 / 17.5 fps. Twenty milliseconds of work
gives you 26 fps, not 50. There is no partial credit for being slightly over.

### Tier 1 — Dart and widget design (largest wins)

**Wrap everything animated in `RepaintBoundary`.** Measured **11.7 ms versus 21.2 ms** for
identical needle drawing — 1.8×, and the difference between making a refresh and missing it.
Cost tracks pixels touched rather than scene complexity, so also keep animated regions
physically small: a needle in a 120×120 box is affordable, the same needle repainting 800×480 is
not.

**Never scale an image at runtime.** 1:1 costs 8.1 ms; 1.7× costs 72–103 ms. Resize every asset
to its exact on-screen pixel size **at build time** and use `FilterQuality.none`. If a decode
must yield something larger, cap it with `cacheWidth`/`cacheHeight` so Skia never holds or
resamples the full-size bitmap. The 2D GPU cannot help here — `M2D_CAP_STRETCHED_BLIT` is
unimplemented in libm2d.

**Avoid everything that forces `saveLayer`**, which allocates an offscreen buffer and composites
it:

| Instead of | Use |
|---|---|
| `Opacity` / `AnimatedOpacity` over a busy subtree | Cross-tween two **opaque** colours |
| `ClipRRect` with `Clip.antiAliasWithSaveLayer` (50 ms) | Pre-render rounded corners into the opaque background |
| `BoxShadow` / Material elevation (43 ms) | A 1 px border, a rule, or a flat colour step |
| `BackdropFilter` blur (180 ms) | Nothing — remove it from the design |
| Stacked translucent layers (280 ms) | Flatten the alpha into opaque colours at design time |
| Full-screen `LinearGradient` (256 ms) | Flat fill, or a small pre-rendered gradient bitmap drawn 1:1 |

**Charts need deliberate construction** — 141 ms for 3 × 267 antialiased 2 px polylines. Note
that decimation alone will *not* save you: 267 points across 800 px is already under one point
per pixel, so the cost is antialiasing and stroke geometry, not point count.

- `isAntiAlias: false` and `strokeWidth: 1`
- `drawRawPoints` with `PointMode.polygon` rather than building a `Path`
- Grid, axes and labels in their own `RepaintBoundary` so only the trace repaints
- Fewer series, or update the trace at a lower rate than the rest of the UI

**Keep the build phase allocation-free.** `const` constructors, static subtrees hoisted out of
`build()`, `AnimatedBuilder` scoped to the smallest leaf that changes. Per-frame allocation means
Dart GC, and on a single core a GC pause is a missed refresh.

**Make backgrounds opaque**, so Skia can skip blending entirely and stacked containers do not
cause overdraw.

**What is comfortably affordable**, for reference: text, large digits, value readouts, progress
bars, switches, lists, 1:1 images and `RepaintBoundary`-bounded animated gauges all measure
6–12 ms against the 19.0 ms budget.

### Tier 2 — system configuration

Everything else on the board competes for the one core.

- `systemd-analyze blame`, then disable what a fielded instrument does not need.
- Reduce journald volume — per-frame logging costs CPU and SD I/O.
- Preload assets at startup so nothing touches the SD card while rendering.
- Check for thermal throttling under sustained load now that the governor is pinned:
  `cat /sys/class/thermal/thermal_zone*/temp` during a scroll.
- Reclaim `cma=192m` in bootargs if the display does not need all of it — on a 1 GB system that
  is page cache you are not getting.
- Governor must be `performance` (the `cpufreq-performance` unit sets this); the board ships
  `conservative`, which idles at 90 MHz of an available 1000.
- `IVI_SW_DRM_FORMAT=rgb565` to match the panel's 16 bpp — measured faster, set by
  `ivi-homescreen-defaults`.

### Tier 3 — a deliberate trade worth considering

**Target 26 fps instead of 52.6.** Because frame rate is quantised, aiming at the second step
roughly halves rendering CPU and leaves the core free for control logic and bus traffic. For an
instrument panel that is often the right trade, and it changes how you pace animations rather
than anything in the stack.

### Tier 4 — investigations, if the above is not enough

**Build a `profile`-mode engine** (a `PACKAGECONFIG` addition plus one engine build) and use
DevTools' timeline. That gives per-primitive raster breakdowns instead of scene-level numbers,
and is the principled way to attack the chart cost rather than guessing.

**Establish whether the XLCDC can upscale.** If it can, rendering at 400×240 quarters the pixels
— potentially 4× on every fill-rate-bound scene, which is most of the over-budget list. **Not
verified:** the `modetest` output shows no scaling property on the planes, so it may not exist.
High ceiling, and cheap to rule in or out from the driver source.

**The flip wait polls at 500 µs** (`sleep_for(500us)`) rather than blocking on the DRM fd. It
does release the core, so this is minor — roughly 38 timer wakeups per frame and up to 500 µs of
latency detecting flip completion, which can occasionally push a frame past a boundary. An
embedder patch to `poll()` the DRM fd would remove both.

### Settled — do not revisit

| Idea | Why not |
|---|---|
| libm2d / 2D GPU offload of the present blit | The swizzle is only 2–4 ms. Needs the compositor API, embedder-allocated backing stores and ~1.5 MB/frame of cache maintenance on a non-coherent GPU — plausibly costing what it saves — and does not touch the flip wait |
| Software OpenGL ES (llvmpipe / softpipe) | llvmpipe segfaults on armv7; softpipe scores `glmark2 Score: 1` |
| `-O3` or other compiler flags | Already `-O2` + LTO + NEON + `-mcpu=cortex-a7`. The hot paths are Skia's hand-written NEON intrinsics and memory traffic; `-O3` risks hurting via I-cache pressure on a 32 KB L1 |
| Hardware line drawing for charts | `M2D_CAP_DRAW_LINES` is unimplemented in libm2d, and Skia would not call it in any case |

## Open items

- **Tearing during scroll (field report), unresolved.** Leading candidate is `IVI_SW_VSYNC=0`
  reaching production — it is a measurement tool and tears by design. Check the *running*
  process, not the unit file. The sink's flip watchdog is a weaker explanation than first
  thought: its deadline is 5 refresh periods (~95 ms), so ordinary scroll load should not trip
  it. See [Troubleshooting](#troubleshooting).
- **Panel-size projections are arithmetic, not measured.** The 1280x800 column in
  [One image, any panel size](#one-image-any-panel-size) scales the 800x480 numbers by pixel
  count. Re-run `flutter-hmi-bench` on any new panel before trusting it.
- **No on-screen keyboard exists in this stack.** `TextField` asks the embedder for one and the
  software backend provides none; with `disable-plugins` the platform channel is not compiled in
  either. Draw a keypad in Dart with `readOnly: true` on the field, or design around text entry.

## Reference

- BSP: <https://github.com/linux4microchip/meta-mchp> (tag `linux4microchip-2026.04`,
  scarthgap / yocto-5.0.15)
- Manifests: <https://github.com/linux4microchip/meta-mchp-manifest>
- meta-flutter: <https://github.com/meta-flutter/meta-flutter> (branch `scarthgap`)
- meta-clang: <https://github.com/kraj/meta-clang> (branch `scarthgap`)
- ivi-homescreen: <https://github.com/toyota-connected/ivi-homescreen> (branch `v3.0`)

The fitted display needs no work: the board DTS has no display nodes, and U-Boot auto-detects
the panel — on an ST7262 it selects the `lvds` overlay from `sama7d65_curiosity.itb` and
appends `video=Unknown-1:800x480-16` to bootargs, with timings carried in the overlay and
driven by `CONFIG_DRM_PANEL_LVDS`. For the panel that is fitted, leave `dt-overlay-mchp`,
`bootargs` and `bootcmd` alone.

**Changing panels is the exception**, and it is a U-Boot change rather than an image or layer
change: only `ST7262` and `HX8394` are auto-detected, so any other panel must have its overlay
and `video=` mode selected explicitly. See
[One image, any panel size](#one-image-any-panel-size).

`CLAUDE.md` in this directory holds the same operational knowledge in a terser form, aimed at
AI coding agents rather than people.
