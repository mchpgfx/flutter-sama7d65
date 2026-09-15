# Microchip Yocto workspace (SAMA7D65 Curiosity)

`repo`-managed Yocto workspace building Microchip's `meta-mchp` BSP for the **SAMA7D65
Curiosity** board. A reusable workflow for these builds lives in the
`microchip-yocto-build` skill — invoke it rather than re-deriving the steps.

## Layout — read this before looking for anything

| What | Where |
|---|---|
| Sources (`repo` manifest) | this directory |
| **Build output** | `~/yocto-build/tmp-glibc/` — **not** under this directory |
| Deploy images | `~/yocto-build/tmp-glibc/deploy/images/sama7d65-curiosity-sd/` |
| sstate / downloads | `~/yocto-build/{sstate-cache,downloads}` |
| `repo` tool | `~/bin/repo` — needs `export PATH="$HOME/bin:$PATH"` |

Build artefacts are redirected because this directory's partition had only ~73 GB free while
`/` has ~440 GB. oe-core appends `-glibc` to `TMPDIR` via `TCLIBCAPPEND`, so the configured
`TMPDIR` of `~/yocto-build/tmp` becomes **`tmp-glibc`** on disk.

## Layers

Manifest-managed (**`repo sync` reverts any edit** — never patch these):
`openembedded-core`, `bitbake`, `meta-openembedded`, `meta-arm`, `meta-mchp`
(at tag `linux4microchip-2026.04`, scarthgap / yocto-5.0.15).

Outside the manifest, safe to edit:
- **`meta-local`** (priority 20) — all local overrides go here
- `meta-clang` (scarthgap) — mandatory for Flutter: both `flutter-engine` and
  `ivi-homescreen` force `TOOLCHAIN = "clang"` + libc++ + compiler-rt
- `meta-flutter` (scarthgap)

## Hard-won constraints

**`meta-local` is load-bearing — do not delete it.** It pins **pseudo 1.9.11**; scarthgap's
pseudo 1.9.0 has no `openat2()` wrapper, and on this host (glibc 2.39 / tar 1.35 / kernel 7.x)
that makes **every** `do_package` fail with `got *at() syscall for unknown directory`.

**`sudo` does not work from the agent session** (no askpass helper). Print the command and
ask the user to run it prefixed with `!`. For flashing on this GNOME/Wayland desktop,
`pkexec` pops a graphical prompt and works where `sudo` cannot.

**AppArmor blocks BitBake** on this Ubuntu 24.04 host. `/etc/apparmor.d/bitbake` grants
`userns` to the BitBake binary only. **It hardcodes the absolute path** — regenerate it if
this workspace moves.

**Parallelism is capped for memory, not cores.** 20 cores but 31 GB shared with a desktop
(Chrome/VS Code hold 6–11 GB) and only 8 GB swap. `BB_NUMBER_THREADS=4`, `PARALLEL_MAKE=-j6`
plus `BB_PRESSURE_MAX_MEMORY`. A previous build at `10 × -j12` was OOM-killed at task 8902 of
8926. **An OOM kill is not a build error** — sstate survives, just re-run to resume.

**Never add a recipe to `meta-local` that `inherit`s a class from a layer not yet added.**
Its `BBFILES` glob (`recipes-*/*/*.bb`) parses immediately and a missing class breaks every
build in the workspace.

**Never report success from a wrapper shell's exit code.** Require BitBake's own `rc=0`
*and* zero `^ERROR` lines. A wrapper exiting 0 around a failed build has already caused one
false "success" here.

**Task counts are not duration.** One task can be an entire LLVM or Flutter-engine build.

## Machine and display

`MACHINE = "sama7d65-curiosity-sd"`, `DISTRO = "mchp-distro"`.

The **800×480 LVDS panel already works** — no BSP/DT work needed. The board DTS has no
display nodes; U-Boot auto-detects the panel and on an **ST7262** selects the `lvds` overlay
from `sama7d65_curiosity.itb`, appending `video=Unknown-1:800x480-16` (16 bpp) to bootargs.
Timings live in the overlay, driven by `CONFIG_DRM_PANEL_LVDS`. Leave `dt-overlay-mchp`,
`bootargs` and `bootcmd` alone.

Note `cma=192m` is reserved in bootargs, off 1 GB total.

## Graphics reality — do not re-litigate

The SoC's Vivante GC is **2D-only**; there is **no hardware OpenGL ES**. Single-core
Cortex-A7 @ 1 GHz.

**Software GLES is a measured dead end** (2026-09-15, `mchp-gles-probe-image`): Mesa 24.0.7
comes up fine (EGL 1.5, GLES 3.2, `kms_swrast`, 800×480), and `llvmpipe (LLVM 18.1.8, 128
bits)` confirms NEON — but **llvmpipe segfaults** on armv7 (LLVM JIT codegen), and softpipe,
which works, scores **`glmark2 Score: 1`** (5 FPS trivial, 3 FPS textured, 1 FPS blur,
75 s/frame for `[terrain]`). Do not rebuild this expecting a different answer.

Benign and expected on this hardware: `MESA-LOADER: failed to open atmel-hlcdc` (correct
fallback to `kms_swrast`) and `Failed to restore original CRTC: -2` on exit.

## Current work: Flutter via Skia CPU → DRM

Flutter is a hard requirement, so the route is **`ivi-homescreen` v3.0's `software` backend**
with `software-sink-drm` — Skia's CPU rasteriser straight into a DRM dumb buffer, no GL at
all. **meta-flutter's README is stale** on this point (it claims no OSS embedder does
software rendering); the CHANGELOG is authoritative.

**Working on hardware as of 2026-09-15.** `flutter-engine` 3.47.4 (armv7, release/AOT),
`ivi-homescreen` 3.0 (software backend), `ivi-homescreen-scroll-bench`, and
`mchp-flutter-bench-image` (463 MB). `readelf -d /usr/bin/homescreen` confirms **no
libGLESv2/libEGL/libgbm/Wayland linkage**, only `libdrm.so.2`. `scroll-bench` renders on the
800×480 panel.

### Running it: the sink MUST be set in the environment

```sh
IVI_SW_SINK=drm-dumb homescreen -b /usr/share/flutter/<app>/3.47.4/release
```

**Without `IVI_SW_SINK` the software backend defaults to `none` and silently discards every
frame** — the display stays blank with no error, only
`[SoftwareBackend] sink: none (frames discarded)` in the log. There is **no CLI flag** for
this and `--help` does not mention it; the `--drm-*` options do **not** reach the software
sink. Valid values (from `strings` on the binary):
`none | memory | file:<pattern> | fbdev[:<device>] | drm-dumb[:<device>] | encoder:file:<path>`
— note it is `drm-dumb`, not `drm`. Success looks like
`[SoftwareBackend] sink: drm-dumb (device='...', 800x480@53.00Hz)`.

Once the sink is live it adopts the panel's native mode, so `-w`/`--height` are unnecessary
(without a sink it reports a bogus default of 1920×720). `--drm-list-modes` is a useful
probe: it enumerates cards/connectors and exits. This board shows **two** connected
connectors (45 and 46), both 800×480@53Hz.

Other `IVI_SW_*` variables, useful for benchmarking: **`IVI_SW_STOP_AFTER_FRAMES`** (render
N frames then exit — makes runs automatable), **`IVI_SW_PROFILE`**, **`IVI_SW_DRM_FORMAT`**
(e.g. `rgb565` — tests whether the 16 bpp panel avoids a per-frame conversion),
`IVI_SW_VSYNC`, `IVI_SW_DRM_DITHER`, `IVI_SW_INPUT`, `IVI_SW_CURSOR`.

### Two runtime dependencies that fail silently

**Fonts are mandatory.** `mchp-headless-image` ships only `libfontconfig1` and **no font
files**, so a Flutter image built on it renders **no text at all** — with no error or log
line. Shapes, lines, images and icons still draw, because app icons come from
`MaterialIcons-Regular.otf` bundled in each app's `flutter_assets`, while Flutter's default
*text* font is resolved from the system through fontconfig. That asymmetry makes it look like
a text-layout bug. Fixed by installing `liberation-fonts`, `ttf-dejavu-{sans,sans-mono,serif}`
and `fontconfig-utils`. On the board, `fc-list | wc -l` and `fc-match sans` distinguish "no
fonts" from "fonts present but unmatched". Add `noto-fonts` if CJK/wider Unicode is needed.

**`xkeyboard-config`** supplies `/usr/share/X11/xkb`; without it libxkbcommon fails
(`failed to add default include path`) and `XkbKeyboard::Create failed`, leaving keyboard
input dead. Touch is unaffected. Now installed.

Both were missed by basing the image on headless to avoid EGT's demos — headless is also
where the fonts and xkb data came from.

### Four non-obvious things this configuration needs

1. **AOT for armv7 works, despite meta-flutter skipping every app recipe on `arm`.**
   The skip guard is over-broad: `flutter build bundle` only produces architecture-*independent*
   bytecode, and the AOT step is separate — the recipe unzips `engine_sdk.zip` from **our
   armv7 engine** and runs its own `gen_snapshot`. So dropping the rejected argument is
   enough:
   ```
   FLUTTER_APP_SUPPORTED_ARCHS = "x64 arm64 riscv64 arm"
   FLUTTER_BUILD_ARGS:remove = "--target-platform linux-arm"
   ```
   **Always verify with `readelf -h` on the packaged `libapp.so`: it must say
   `Machine: ARM`.** A build that succeeds while emitting host x86-64 code is a false pass.
   See [[flutter-no-armv7-app-bundles]].
2. **`meta-local/recipes-graphics/toyota/ivi-homescreen_3.0.bbappend` adds
   `virtual/libgles2`.** A software-only build still fails to *compile* without the GLES
   headers, because `flutter_desktop_texture_registrar.h` includes `<GLES2/gl2.h>`
   unconditionally. Headers only — nothing links GL.
3. **`disable-plugins` is required, not a preference.** With the software backend the plugin
   tree fails: `generated_plugin_registrant.cc: use of undeclared identifier
   'FlutterDesktopGetPluginRegistrar'`. The v3.0 embedder builds against the plugins *v2.0*
   branch, evidently only exercised with EGL backends. **Consequence for the product, not
   just the build: platform integration via plugins is currently unavailable.** Prefer
   `dart:ffi` (call C libraries straight from Dart) or a separate daemon over a socket.
4. **`hud` is omitted deliberately** — it requires `compositor`, draws every frame
   (contaminating the measurements) and changes the presentation path.

Other `local.conf` settings: `DISTRO_FEATURES:append = " opengl"` (needed *only* because
`flutter-engine` has `REQUIRED_DISTRO_FEATURES = "opengl"`; it depends on no GL
implementation); `PACKAGECONFIG:pn-flutter-engine` = **`release` only** (the recipe default
`debug profile release` is three complete engine builds); no engine `lto` yet — revisit only
if measurements land near the 33 ms budget.

**The pattern across all of this: the software backend is untrodden upstream.** Every
failure so far has been code assuming an EGL backend exists. Expect more of the same, and
prefer supplying what the build asks for over enabling a GL backend to satisfy it.

### Third-party apps (meta-flutter-apps): two traps, both handled

`meta-flutter-apps` is a **separate layer** inside the meta-flutter checkout
(`flutter-apps-layer`); adding `meta-flutter` alone leaves its ~220 recipes invisible with
`Nothing PROVIDES`. It is now in `bblayers.conf`. Listing recipe files with `find` proves
nothing about visibility — check with `bitbake -e <recipe>`.

174 of those 220 recipes **never set `S`**, assuming newer oe-core aligns the git fetcher
with `S = ${WORKDIR}/${BP}` via `BB_GIT_DEFAULT_DESTSUFFIX`. Scarthgap has no such variable
— git unpacks to `${WORKDIR}/git` — so `do_populate_lic` and `do_archive_pub_cache` fail on a
nonexistent path. Fixed with one-line bbappends in
`meta-local/recipes-flutter-apps/apps/<app>_%.bbappend` setting `S = "${WORKDIR}/git"`.
**Deliberately not fixed globally:** `BB_GIT_DEFAULT_DESTSUFFIX` would change the unpack
destination for every git recipe and break the many that set `S = "${WORKDIR}/git"` on
purpose (pseudo, ivi-homescreen, dt-overlay-mchp).

**Viability rule:** with `disable-plugins`, an app builds **iff it has no Linux plugin
dependencies**. The recipe refuses loudly — `.flutter-plugins-dependencies lists Linux
plugins (window_size) but no registrant was generated` — rather than shipping an app whose
plugins silently never register. Treat that message as definitive, not as something to work
around. Build batches with `bitbake -k` so one refusal does not hide the rest.

Also worth knowing: **no chart/graph app exists** among the 220, so plots must be a custom
app (`fl_chart` / `syncfusion_flutter_charts` are pure Dart and work without plugins).

**Engine build costs:** OOM-killed twice at `BB_NUMBER_THREADS=4`/`-j6`. The engine's
`do_package` (splitting debug symbols from a very large `.so`) wants the machine to itself —
`BB_NUMBER_THREADS=1` finished it. Once built it is in sstate; a `PACKAGECONFIG` change
(e.g. back to `release` after trying `jit_release`) restores from cache rather than
recompiling.

**Fallback if AOT ever breaks:** `jit_release` ships architecture-independent
`kernel_blob.bin`. But meta-flutter's JIT path has **never been executed** — `common.inc`
line 521 calls `run_command(cmd, source_root, env)`, omitting the leading `d` that all other
call sites pass, so it raises `TypeError`. One-line fix; worth reporting upstream.

Goal is a **GUI design-constraints table** against a **30 FPS / 33 ms** budget, covering
gauges, lists, status screens and media/charts. Frame timings come from the app via
`SchedulerBinding.addTimingsCallback`, reporting **build vs raster separately** (a CPU
rasteriser should be raster-bound; build-bound would be a different, fixable problem) and
**median + p95**, since jank matters more than the mean.

Plan: `~/.claude/plans/wobbly-orbiting-peach.md`.

## Commands

```sh
export PATH="$HOME/bin:$PATH"
source openembedded-core/oe-init-build-env build     # never pipe this: the pipe
                                                     # subshells it and the cd is lost
MACHINE=sama7d65-curiosity-sd bitbake <image>
```

Validate cheaply before long builds: `bitbake -n <target>`, then
`bitbake -c package base-files` as a pseudo guard. Do not run `bitbake-getvar` while a build
is running — it blocks on the server lock.

Images: `mchp-graphics-image` (EGT, known-good fallback), `mchp-headless-image`,
`mchp-gles-probe-image` (local, softpipe GLES baseline), `mchp-flutter-bench-image` (local,
Flutter + software backend + benchmark apps).

Flashing needs root, which the agent session cannot do. Unmount first as a **separate**
command — a failed `umount` in a `&&` chain silently skips the write:

```sh
udisksctl unmount -b /dev/mmcblk0p1 ; udisksctl unmount -b /dev/mmcblk0p2
pkexec dd if=<image>.wic of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

`/dev/mmcblk0` is the SD card slot (59.7 GB); the system disk is `/dev/nvme0n1`. Verify the
target before every write, and check afterwards that the old image's files are gone.
