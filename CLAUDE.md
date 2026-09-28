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

## Version control

**`meta-local` is a git repo of its own** — remote `origin`
`ssh://git@bitbucket.microchip.com/mg/flutter.git`, branch `master`, tracking
`origin/master`. Nothing else in this workspace is tracked here (the `repo`-managed layers are
pinned by manifest tag; `build/` is regenerable and tens of GB).

History goes **straight to `master`**; there is no PR flow in use, though Bitbucket offers one
on push. Commit inside `meta-local`, not from the workspace root — the workspace root is not a
git repository.

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
Timings live in the overlay, driven by `CONFIG_DRM_PANEL_LVDS`. For the fitted panel, leave
`dt-overlay-mchp`, `bootargs` and `bootcmd` alone — but note that **switching** panels is
exactly a `bootargs`/overlay change, and only `ST7262` and `HX8394` are auto-detected. See
"One image, any panel size" below.

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

**`mchp-flutter-gallery-image` confirmed on hardware 2026-09-16** (537 MB) — user-verified
end to end: boots to the demo menu unattended, both demos launch, and the USER button returns
to the menu. That took four bugs to get there; see
"The auto-start kiosk path" below before touching the launcher, the unit or `userbtn-wait`.

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
implementation); `PACKAGECONFIG:pn-flutter-engine` = the recipe's own default set **minus
`debug` and `profile`** (the default `debug profile release` is three complete engine builds),
**plus `lto`**, enabled 2026-09-15 — worth the build time, but the workload is fill-rate bound
so expect single-digit to low-double-digit percent, not a transformation. `lto` is also on for
`ivi-homescreen`, where it is cheap. Never add `slimpeller`: it strips Skia.

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

### Performance: settled, and the budget is 19.0 ms not 33 ms

The panel is **52.64 Hz = 19.0 ms/refresh**. `DrmDumbSink::Present()` busy-waits on
`flip_pending_` for the previous page flip, double-buffered, so **frame rate is quantised**:
52.6 / 26.3 / 17.5 fps. A screen needing 20 ms runs at 26 fps, not 50. Design to **19.0 ms**
of build + raster.

**A constant per-frame floor is pacing, not cost.** Cheap scenes all reported raster
18.4-18.9 ms regardless of content because that is the flip wait. `IVI_SW_VSYNC=0` does not
move it (that gates the engine's vsync baton, a different mechanism) — read the sink's
`Present()` rather than inferring from experiments.

**Content-only costs** (`IVI_SW_SINK=none`, frames discarded): progress bars 6.2, big digits
7.7, opacity/saveLayer 7.9, image 1:1 8.1, fullscreen fill 8.8, value updates 8.4, lists
11-15, **needle WITH RepaintBoundary 11.7 vs 21.2 WITHOUT** (a real 1.8x on identical
drawing). Over budget: arc+ticks 32, BoxShadow 43, ClipRRect AA 50, image scaled 72-103,
charts 141, blur 180, gradient 256, alpha stack 280.

**Measurement traps.** `IVI_SW_SINK=memory` is NOT a neutral baseline — it was *slower* than
the display path (charts 46 -> 151) with `buildDuration` rising too, i.e. system-wide
contention from cacheable writes and per-frame allocation versus the dumb buffer's
write-combining streaming map. Use `none`. But even `none` removes pacing, so **expensive**
scenes inflate through thread contention on the single core; trust `none` for sub-refresh
scenes and drm-dumb for the rest. `baseline.static_text` runs first and is a warm-up artefact.

### libm2d: enabled, deliberately not used

The GPU works (see [[sama7d65-2d-gpu-enablement]]) but the only operation it could take over
is the present blit, worth **2-4 ms**. It would need the compositor API, embedder-allocated
`m2d_alloc` backing stores, and ~1.5 MB/frame of cache maintenance on a non-coherent GPU —
plausibly costing what it saves — and would not touch the flip wait.
`M2D_CAP_STRETCHED_BLIT` and `M2D_CAP_DRAW_LINES` are `/* not implemented yet */` in libm2d
(software gaps, not hardware limits), so no scaling or chart help either. If offloading is
revisited, the display controller's **two overlay planes** are the better target — no GPU, no
cache maintenance, no patched embedder. See "Overlay planes" below for what they can actually
do, read out of the driver rather than from the `modetest` listing.

### The present blit: what the format actually costs, and why ARGB is not a shortcut

Read `shell/backend/software/drm_dumb_sink.cc` and `pixel_swizzle.h` at the pinned
`HOMESCREEN_COMMIT` (`131cbc37`) before theorising about this. `Present()` calls
`SwizzleInto()`, which dispatches on `IVI_SW_DRM_FORMAT`:

| Format | Function | Per-pixel work |
|---|---|---|
| `rgb565` | `FlutterToRGB565` | `vld4_u8` deinterleave + widening-shift + 2× `vsri` to pack 5/6/5 |
| `xrgb8888` (default) | `FlutterToBGRX8888` → `CopyWithAlphaForce` | `vld1q_u8` + `vorrq_u8` + `vst1q_u8` — a NEON memcpy forcing alpha to 0xFF |

**Switching to XRGB/ARGB does not remove a pass over the frame.** There is no format in which
the CPU stops touching every pixel: Skia renders into *engine-owned* memory and `Present()`
receives a pointer to it, so the copy exists because source and scanout are different
allocations — not because of colour conversion. XRGB is already near-minimal (load, OR, store).

**And the bandwidth goes the wrong way.** At 800x480, source is always 4 B/px:

```
RGB565    read 1500K + write  750K = 2250K/frame  (40 MB/s at 52.6 Hz)
XRGB8888  read 1500K + write 1500K = 3000K/frame  (81 MB/s)  = +33%
```

Which is why 16 bpp measured faster on hardware. The 565 pack spends a few more ALU ops and
writes half the bytes; on this part memory traffic dominates. Keep
`IVI_SW_DRM_FORMAT=rgb565`.

### Overlay planes: RGB565 blends fine — ARGB is NOT required

The natural assumption is that hardware-compositing an overlay onto the base needs an alpha
channel. **The driver says otherwise.** `atmel_hlcdc_plane.c` (XLCDC path, ~line 487) sets the
blend factors unconditionally for every non-primary plane
(`SFACTC_A0_MULT_AS`, `DFACTC_M_A0_MULT_AS`, `SFACTA_ONE`, `DFACTA_ONE`) and then:

```c
if (format->has_alpha)
        cfg |= ATMEL_XLCDC_LAYER_A0(0xff);              /* per-pixel alpha; A0 pinned opaque */
else
        cfg |= ATMEL_XLCDC_LAYER_A0(state->base.alpha); /* the DRM plane alpha property */
```

So **the overlay blends either way**; the alpha channel only decides where the coefficient
comes from. `drm_plane_create_alpha_property()` (~line 1021) exposes that property to
userspace.

| Want | Overlay format | Cost |
|---|---|---|
| Fade/dim a whole overlay | **RGB565** + plane `alpha` property | 2 B/px |
| Hard-edged overlay, transparent background | **RGB565** + `chroma_key` | 2 B/px |
| Soft per-pixel edges | ARGB8888 (`A0` forced to 0xff) | 4 B/px |

**Which plane gets which property** (`atmel_hlcdc_plane.c`, ~line 1015) — the gating is exact:

| Property | Condition | So on sama7d65 |
|---|---|---|
| `alpha` | `type` is OVERLAY or CURSOR | `overlay1`, `high-end-overlay` — **not** `base` |
| `rotation` (0/90/180/270) | `layout.xstride[0] && layout.pstride[0]` | `overlay1`, `high-end-overlay` — **not** `base` (its layout has `xstride` but **no** `pstride`) |
| CSC (YUV) | `layout.csc` | `high-end-overlay` only |

So the base layer has neither alpha nor rotation, which matters if rotation was the goal:
**the full-screen Flutter surface cannot be rotated by the display controller.** Only overlays
can.

`sama7d65` layers (`atmel_hlcdc_dc.c`, `atmel_xlcdc_sama7d65_layers`): `base`, `overlay1`, and
`high-end-overlay`. **Both overlays carry `chroma_key` and `chroma_key_mask`** — colour-keyed
transparency at 16 bpp, which covers most HMI cases (needle, popup, status bar) with no alpha
channel at all. `high-end-overlay` additionally has `scaler_config`/`hxs_config`/`vxs_config`
and the YUV format list. All three planes advertise `RGB565`, `XRGB8888` **and** `ARGB8888`
(`rgb_formats[]`), so format choice is free at the DRM level.

**The base layer stays RGB565 regardless** — nothing about an overlay forces the full-screen
surface Flutter repaints every frame to 32 bpp, which is the traffic that matters.

**Unverified, check before designing on it:** `atmel_hlcdc_plane.c:678` tests
`ovl_s->fb->format->has_alpha || ovl_s->alpha != DRM_BLEND_ALPHA_OPAQUE`, probably gating the
"disc area" optimisation (punching a hole in the base layer so hidden pixels are not fetched).
If so, a *translucent* overlay forfeits that saving. Not traced.

**The real blocker is unchanged and is not the format: Flutter hands the embedder ONE layer.**
Getting distinct elements onto separate DRM planes needs the compositor API plus platform
views — unproven on this embedder, and `disable-plugins` removes the usual machinery.

### Before any of this: measure the swizzle directly

The **2-4 ms** figure is an *inference* from the 10-12.5 ms gap between in-situ and
content-only runs, and most of that gap is the flip wait. `IVI_SW_PROFILE` plus
`IVI_SW_STOP_AFTER_FRAMES` gets a direct number in one boot with no code written. **If the
swizzle is under a millisecond, every GPU and overlay-plane question above is closed on
arithmetic.** Do not build anything here until that number exists.

Related: there is **no NEON-vs-GPU benchmark** and never was. NEON was never a toggleable
variable (Skia and `pixel_swizzle.h` are already NEON, the tune is
`cortexa7hf-neon-vfpv4`), and no Flutter frame has ever gone through libm2d. The only
GPU-adjacent *score* on record is `glmark2 Score: 1` — which is **software** GL on the CPU
(softpipe), not the 2D GPU. Do not conflate them.

### Field findings from the customer pilot

**Pin the connector.** The sink takes the first connector that is `connected` with >=1 mode,
and **LVDS has no hotplug detect** so all LVDS connectors report connected regardless of what
is fitted. This board shows LVDS-1 and LVDS-2 with identical modes but one encoder (44) and
one CRTC (43); LVDS-2 has encoder 0. Selection reduces to enumeration order and can bind an
undrivable output — intermittent blank screen. Pass `--drm-connector LVDS-1`; pinned, it fails
loudly instead of silently.

**Never ship `IVI_SW_VSYNC=0`.** Measurement tool only; it tears. Check the running process,
not the unit file: `tr '\0' '\n' < /proc/$(pgrep -x homescreen)/environ | grep ^IVI_`. If it
is unset and tearing persists, grep for `force-clearing flip_pending_` — the watchdog
submitting a flip mid-scanout because the completion event was not serviced in time.

### One image, any panel size — and the readout must be live

Nothing in the rootfs is tied to 800x480. XLCDC allows **2048x2048**
(`atmel_hlcdc_dc.c`, `atmel_xlcdc_dc_sama7d65`), the software sink adopts the connector's
current mode, and Flutter lays out from the view size. **Switching panels is a
bootargs/overlay change, not an image change** — U-Boot picks the overlay carrying the
timings.

**Never hardcode the resolution in UI text.** The menu did (`'… · 800×480 · …'`) and would
have kept claiming 800x480 on a 1280x800 panel. It now reads
`View.of(context).physicalSize`, `Display.refreshRate` (wrapped in try/catch — it resolves
through a nullable map on the platform dispatcher and the software embedder may register no
Display, so the resolution must not depend on it), and `/proc/cpuinfo` `Features` for
NEON/VFPv4. On x86 that field reads `NEON unknown`, which is correct: x86 cpuinfo has no
`Features` line, it uses `flags`.

**Two Dart gotchas hit here:** `num.clamp()` returns **`num`**, so `.toDouble()` is required
before the value reaches a `double` parameter; and in a `cond ? 0 : 18 * s` the int literal
should be written `0.0`.

**`test/menu_layout_test.dart` is the regression guard** — no overflow from 480x272 to
2048x2048 plus two portrait sizes, and the status line must contain the live resolution. It
immediately caught a real design error: stacking the tiles when *width* was small is
backwards, because stacking doubles the height needed and a short landscape panel then
overflows. Stack on **portrait aspect**, not narrow width. Run it with the SDK from the
sysroot and `PUB_CACHE` pointed at the SDK's own `.pub-cache` (`--offline` works); see
README.

**The New Vision 10.1" panel is already in the FIT as config `lvds_newvision`** —
1280x800, 65 MHz pixel clock, h-blank 32/48/80, v-blank 8/8/16, 216x135 mm, and it carries
`atmel,maxtouch` so touch comes with it. Refresh is 65e6/(1440x832) = **~54.2 Hz, an 18.4 ms
budget** (read out of the built `.itb`, not a datasheet). **U-Boot will not select it:** the
env tests only `ST7262` -> `lvds` and `HX8394` -> `mipi`, so `display_var` stays empty and
neither the overlay nor a `video=` bootarg is applied. It must be set explicitly; README has
an env snippet, marked as derived from the env file rather than tested.

**A bigger panel costs proportionally more CPU.** 1280x800 is **2.67x** the pixels of
800x480 and the per-refresh budget does not grow, so the measured constraints table is
specific to 800x480 and tightens on anything larger. The projected numbers in the README are
arithmetic on pixel count, **not measurements** — re-run `flutter-hmi-bench` on the new
panel.

### The auto-start kiosk path: what actually broke (and one wrong diagnosis)

**The real bug was `HS_PID=$(run_bundle ...)` in the launcher.** Returning a background
child's PID through a command substitution fails twice: the backgrounded `homescreen`
inherits the substitution's stdout pipe and holds it open, so `$( )` blocks until the demo
exits — the `userbtn-wait &` on the next line is **never reached** — and `log()` output is
captured into the value, so `$HS_PID` is a log line with a number appended and every
`kill -0`/`kill -TERM` on it fails. The tell on the board: the service cgroup showed the
launcher plus `homescreen` and **no `userbtn-wait` process anywhere**. Start children in the
caller's shell, assign `$!` to a variable, and log to **stderr**. Reproduce in 5 lines:
`f(){ echo log; sleep 6 & echo $!; }; time X=$(f); echo "[$X]"`.

**The button was never broken.** `/proc/bus/input/devices` shows `N: Name="gpio-keys"`,
`H: Handlers=kbd event1`, `B: KEY=800` — bit 11, exactly `KEY_0` — and homescreen logs
`KeyCallback: keysym: 48` (ASCII `'0'`) on every press. The DTS is right: `PIN_PC10`,
`GPIO_ACTIVE_LOW`, `linux,code = <KEY_0>`.

**A wrong diagnosis worth not repeating.** I claimed the evdev name was the empty string,
reasoning that `gpio_keys.c` falls back to `pdev->name` (true: `input->name = pdata->name ? :
pdev->name`, and `pdata->name` is the `label` of the *parent* node, which this DTS omits) and
that `of_device_alloc()` leaves `pdev->name` as `""` from `platform_device_alloc("", …)` (also
true). The step I missed: **`of_device_add()` (`drivers/of/platform.c:51`) then does
`ofdev->name = dev_name(&ofdev->dev)`**, which `of_device_make_bus_id()` set to `gpio-keys`.
I read one function and stopped before the one that runs next. Reading two of three functions
in a chain and calling it "confirmed from source" is how this happened — `cat
/proc/bus/input/devices` would have cost one command and settled it first.

`userbtn-wait` now matches by **capability** anyway (`EVIOCGBIT(EV_KEY, …)`, test `KEY_0`),
which is more robust than either name — but the name match would have worked. Note the keybit
map is an array of *kernel* `unsigned long`: 32-bit on this armv7 target, 64-bit on the build
host, so index with `sizeof(long)`. A USB keyboard also emits `KEY_0`, so candidates that also
have `KEY_A` are demoted.

**A watcher's failure must not look like success.** `userbtn-wait` originally returned 1 when
it found no device and the launcher treated *any* exit as a press, so a broken button would
have ejected the user from every demo. Now `0` = pressed, `2` = no device, `3` = read error,
and only `0` returns to the menu.

**Confirmed working end to end on 2026-09-16** — unattended boot to menu, both demos, and
the button returning to the menu. Everything below is the record of how, not an open problem.

**Still unresolved: why the unit did not start on the *first* image.** It is `enabled` and now
runs (`active (running)`, `No jobs running`). I removed a `Wants=`/`After=dev-dri-card0.device`
dependency on the theory that it blocked startup, and that dependency *is* genuinely unsound —
`99-systemd.rules` in this image tags `tty`, `block`, `net`, `sound`, `usb`, `ubi`, `ptp`,
`bluetooth`, `udc`, `rfkill` and **nothing in the `drm` subsystem**, so `dev-dri-card0.device`
can never activate. But I never confirmed it was the cause, and `Wants=` is supposed to
tolerate a failed dependency. Do not treat that as a diagnosed bug. The launcher now polls for
`/dev/dri/card*` itself, which is the right shape regardless.

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
Flutter + software backend + benchmark apps), **`mchp-flutter-gallery-image`** (local, boots
to the demo menu; despite the name it is no longer gallery-specific).

**Scripting a build needs bash and no `set -u`.** `oe-init-build-env` is not dash-compatible
(`source: not found`) and reads unset variables (`BBSERVER: unbound variable`), so a wrapper
using `sh` or `set -u` exits before bitbake ever runs — and does so with a status that can
look like success. Both happened here; only the `^ERROR`-count-plus-`rc=` check caught it.

Flashing needs root, which the agent session cannot do. Unmount first as a **separate**
command — a failed `umount` in a `&&` chain silently skips the write:

```sh
udisksctl unmount -b /dev/mmcblk0p1 ; udisksctl unmount -b /dev/mmcblk0p2
pkexec dd if=<image>.wic of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

`/dev/mmcblk0` is the SD card slot (59.7 GB); the system disk is `/dev/nvme0n1`. Verify the
target before every write, and check afterwards that the old image's files are gone.
