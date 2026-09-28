# Building the SAMA7D65 Flutter demo from scratch

Step-by-step for a fresh Linux machine: clone, build, flash, boot into the Flutter demo menu.
Nothing here assumes you have seen this project before.

`README.md` is the reference for *why* the configuration is the way it is, and for the measured
GUI constraints. This file is only the procedure.

**What you get at the end:** an SD card that boots straight into a Flutter menu on the board's
800×480 panel, offering the Flutter Gallery and the Material 3 demo. The USER button (PC10)
returns from a demo to the menu.

**How long:** a first build is **4–8 hours** on a 20-core / 31 GB machine — most of it the
Flutter engine and LLVM — and longer on a smaller one. Plan for it to run overnight. Rebuilds
after a change are minutes.

---

## 0. What you need

| | |
|---|---|
| OS | Ubuntu 24.04 is what this is verified on. Any distro Yocto scarthgap supports will work, but the package names and the AppArmor step below are Ubuntu-specific. |
| Disk | **~90 GB free**, on one filesystem if possible. Measured for this exact build: `tmp-glibc` 33 GB, `downloads` 29 GB, `sstate-cache` 12 GB = **74 GB**, plus headroom. (`rm_work` is enabled in the template, which is why this is not 150 GB.) |
| RAM | **16 GB minimum, 32 GB comfortable.** The template caps parallelism for memory, not cores — see step 3 if you have less. |
| Network | The first build downloads ~29 GB. |
| Hardware | SAMA7D65 Curiosity board, its 800×480 LVDS panel, a microSD card (≥ 2 GB), and a card reader. |

Do **not** run any of this as root, and do not use a `sudo`-owned build directory. BitBake
refuses to run as root, and a mixed-ownership `tmp` directory is painful to unpick.

---

## 1. Host packages

```bash
sudo apt-get update
sudo apt-get install -y gawk wget git-core git-lfs diffstat unzip texinfo gcc-multilib \
  build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils \
  debianutils iputils-ping python3-git python3-jinja2 libegl1 libsdl1.2-compat-dev \
  pylint xterm zstd liblz4-tool file locales libacl1
```

Microchip's published list is stale on 24.04 — this one is corrected: `pylint3`→`pylint`,
`libegl1-mesa`→`libegl1`, `libsdl1.2-dev`→`libsdl1.2-compat-dev`.

Yocto needs a UTF-8 locale:

```bash
sudo locale-gen en_US.UTF-8
```

---

## 2. The AppArmor profile — mandatory on Ubuntu 24.04

**BitBake will not run without this.** Ubuntu 24.04 restricts unprivileged user namespaces, and
BitBake needs them. The failure is an opaque `Unable to create user namespace` during setscene.

The narrow fix grants the capability to the BitBake binary alone, rather than disabling the
protection machine-wide. Choose your workspace directory first, because **the profile hardcodes
an absolute path**:

```bash
mkdir -p ~/yocto && cd ~/yocto          # or wherever; remember this path

sudo tee /etc/apparmor.d/bitbake >/dev/null <<EOF
abi <abi/4.0>,
include <tunables/global>
profile bitbake $PWD/bitbake/bin/bitbake flags=(unconfined) {
  userns,
  include if exists <local/bitbake>
}
EOF

sudo apparmor_parser -r /etc/apparmor.d/bitbake
```

(`$PWD/bitbake/bin/bitbake` does not exist yet — step 4 creates it. The profile is fine to
install first.)

**If you ever move the workspace, regenerate this file.** A stale path means the profile silently
stops matching and builds start failing again.

The blunt alternative, if your site policy prefers it:
`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` — but that lowers it for every
process on the machine.

---

## 3. Get `repo`

The Microchip BSP is a `repo`-managed manifest of ~20 git repositories.

```bash
mkdir -p ~/bin
curl -sSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo
chmod a+x ~/bin/repo
export PATH="$HOME/bin:$PATH"          # add to ~/.bashrc to make it stick
```

---

## 4. Clone and fetch the workspace

```bash
cd ~/yocto                                    # the directory from step 2
git clone ssh://git@bitbucket.microchip.com/mg/flutter.git meta-local
./meta-local/setup-workspace.sh
```

That script fetches the Microchip BSP at tag `linux4microchip-2026.04`, then clones the two
layers that are **not** in that manifest at **pinned commits**:

| Layer | Pinned revision |
|---|---|
| `meta-clang` | `cc29beb210ab94eacc53bbd67e287e4e33ede342` (scarthgap) |
| `meta-flutter` | `719826d2f71076fb616ffea59ee413ad3c62ccba` (scarthgap) |

The pinning is deliberate: following the branch tip would silently change the Flutter engine
version and every app bundle with it. They sit outside the manifest so `repo sync` cannot revert
them.

`meta-clang` is **not optional** — both `flutter-engine` and `ivi-homescreen` force
`TOOLCHAIN = "clang"` with libc++ and compiler-rt. GCC cannot build this stack.

Expect this step to take a while and pull several GB.

---

## 5. Configure the build

```bash
cd ~/yocto
export TEMPLATECONF=../meta-local/conf/templates/default
source openembedded-core/oe-init-build-env build
```

**Do not pipe that `source` line** (`| tee`, `| grep`, …). A pipe runs it in a subshell and the
directory change is lost.

That is the entire configuration step. The template in `meta-local` seeds
`build/conf/local.conf` and `build/conf/bblayers.conf` with every setting this project needs,
including `MACHINE = "sama7d65-curiosity-sd"`, `DISTRO = "mchp-distro"`, and the full layer list.

**`TEMPLATECONF` is read only when `oe-init-build-env` first creates a build directory.** If you
later pull template changes from git, either use a fresh build directory or copy
`meta-local/conf/templates/default/*.sample` over `build/conf/` by hand — a `git pull` alone
changes nothing about an existing build.

### If your machine has less than 32 GB of RAM

The template ships `BB_NUMBER_THREADS = "4"` and `PARALLEL_MAKE = "-j6"`, with
`BB_PRESSURE_MAX_MEMORY` throttling on top. Those numbers are deliberately below what 20 cores
could do: this build has been OOM-killed twice at higher settings, once at task 8902 of 8926.

On 16 GB, edit `build/conf/local.conf`:

```conf
BB_NUMBER_THREADS = "2"
PARALLEL_MAKE = "-j4"
```

If you want somewhere other than `build/` for the large directories, set them now:

```conf
TMPDIR = "/path/with/space/tmp"
SSTATE_DIR = "/path/with/space/sstate-cache"
DL_DIR = "/path/with/space/downloads"
```

Note oe-core appends `-glibc` to `TMPDIR`, so a configured `.../tmp` appears as
**`tmp-glibc`** on disk. This trips people up when looking for output.

---

## 6. Build

```bash
bitbake mchp-flutter-gallery-image
```

Run it under `screen`/`tmux`, or log it and walk away:

```bash
bitbake mchp-flutter-gallery-image 2>&1 | tee ~/build.log
```

### Judging whether it worked

**Do not trust a wrapper script's exit status.** If you script this, `oe-init-build-env` is not
dash-compatible (`source: not found`) and reads unset variables (`BBSERVER: unbound variable`),
so a wrapper using `sh` or `set -u` can exit **0** having never run BitBake at all. Require both:

```bash
grep -c '^ERROR' ~/build.log        # must be 0
tail -3 ~/build.log                 # must end with a Tasks Summary, all succeeded
```

### If it gets OOM-killed

**An OOM kill is not a build error.** sstate survives; just run the same command again and it
resumes. If it dies repeatedly in the same place — the Flutter engine's `do_package` is the usual
suspect, splitting debug symbols out of a very large `.so` — give that one task the machine:

```bash
BB_NUMBER_THREADS=1 bitbake mchp-flutter-gallery-image
```

### Other things worth knowing mid-build

- **Task counts are not progress.** One task can be an entire LLVM or Flutter-engine build, so
  "200 tasks left" can still mean hours.
- **Never edit a recipe or conf file while a build is running.** One reparse mid-build costs the
  tail of the run with `basehash value changed ... metadata is not deterministic`.

---

## 7. Verify the image before flashing

```bash
cd ~/yocto/build
D=$(ls -d tmp-glibc/deploy/images/sama7d65-curiosity-sd)   # if you moved TMPDIR in step 5,
                                                          # use $YOUR_TMPDIR-glibc/deploy/... instead
M=$D/mchp-flutter-gallery-image-sama7d65-curiosity-sd.rootfs.manifest

ls -lh $D/mchp-flutter-gallery-image-sama7d65-curiosity-sd.rootfs.wic   # ~537 MB
grep -E '^(flutter-demo-launcher|flutter-demo-menu|userbtn-wait|ivi-homescreen|flutter-engine) ' $M
```

All five must be listed. Two things that are easy to get wrong and produce a *silently* broken
system, worth confirming once:

```bash
# The app snapshot must be ARM, not host x86-64. A build can succeed while emitting host code.
# Read it out of the rootfs tarball: the template enables rm_work, so tmp-glibc/work is gone.
tar xzf $D/mchp-flutter-gallery-image-sama7d65-curiosity-sd.rootfs.tar.gz \
    -C /tmp ./usr/share/flutter/flutter_demo_menu/3.47.4/release/lib/libapp.so
readelf -h /tmp/usr/share/flutter/flutter_demo_menu/3.47.4/release/lib/libapp.so | grep Machine
# expect: Machine: ARM

# Fonts must be present, or every screen renders shapes and icons but NO TEXT, with no error.
grep -c 'ttf-dejavu\|liberation-fonts' $M      # expect 4
```

---

## 8. Flash the SD card

**Identify the device first.** Writing to the wrong one destroys a disk:

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
```

A card reader typically shows as `/dev/mmcblk0` or `/dev/sdX` — match the **size** to your card.
An NVMe system disk (`/dev/nvme0n1`) is never the target.

Unmount as its **own command**, then write:

```bash
udisksctl unmount -b /dev/mmcblk0p1 ; udisksctl unmount -b /dev/mmcblk0p2

sudo dd if=$D/mchp-flutter-gallery-image-sama7d65-curiosity-sd.rootfs.wic \
        of=/dev/mmcblk0 bs=4M conv=fsync status=progress
sync
```

**Do not chain `umount && dd`.** If the unmount fails — including just failing to prompt for a
password — `&&` skips the write and you get a success-looking no-op with the old image still on
the card. This has happened here.

On a desktop session where `sudo` cannot open a terminal to prompt, use `pkexec dd ...` instead;
it raises a graphical prompt.

Afterwards, confirm the card holds the *new* image (mount it and check timestamps, or just
re-read the partition table with `lsblk`).

---

## 9. Boot

Insert the card, power the board. Expected sequence:

1. U-Boot detects the ST7262 panel and selects the `lvds` overlay, appending
   `video=Unknown-1:800x480-16` to the kernel command line.
2. `cpufreq-performance.service` pins the CPU governor to `performance` — the board otherwise
   idles at 90 MHz of an available 1000, and with no GPU the clock *is* the frame rate.
3. `flutter-demo-launcher.service` waits for `/dev/dri/card0`, then starts the Flutter menu.
4. Tap a demo. The menu exits and that demo starts. Press the USER button (PC10) to come back.

The menu's own status line reports what it actually found, e.g.
`Skia CPU · 800x480 @ 52.6 Hz · NEON+VFPv4 · no GPU`, which is the quickest confirmation that
the panel and CPU features came up as expected.

### If the screen stays blank

```bash
systemctl status flutter-demo-launcher --no-pager
journalctl -u flutter-demo-launcher -b
```

Look for `[SoftwareBackend] sink: drm-dumb (device=..., 800x480@53.00Hz)`. If it instead says
`sink: none (frames discarded)`, `IVI_SW_SINK` is not reaching the process — the launcher exports
it, so that would mean the launcher is not what started homescreen.

`README.md` has a fuller troubleshooting section, including the three failure modes seen during
development and the commands that distinguish them.

---

## Other build targets

```bash
bitbake mchp-flutter-bench-image     # Flutter + the 23-scene render benchmark
bitbake mchp-graphics-image          # Microchip's stock EGT image - known-good fallback
bitbake mchp-headless-image          # no graphics stack
```

`mchp-graphics-image` is worth knowing about: if you are unsure whether a problem is your build
or the board, that one is Microchip's own and rules out the hardware.

---

## Making changes

All local overrides live in `meta-local` — it is a git repository of its own, and the only
tracked part of the workspace. The `repo`-managed layers are pinned by manifest tag, and **any
edit to them is silently reverted by the next `repo sync`**, so never patch `openembedded-core`
or `meta-mchp` directly.

To change the demo apps, the launcher, or the kiosk behaviour, look in:

```
meta-local/recipes-flutter/flutter-demo-menu/      the menu app (Dart)
meta-local/recipes-mchp/flutter-demo-launcher/     the supervisor script + systemd unit
meta-local/recipes-mchp/userbtn-wait/              the USER button watcher (C)
meta-local/recipes-mchp/images/                    image definitions
```

Flutter app changes can be checked **on the host**, in seconds, without an image build:

```bash
# $TMPDIR-glibc, i.e. build/tmp-glibc unless you moved TMPDIR in step 5.
SDK=$(ls -d ~/yocto/build/tmp-glibc/sysroots-components/x86_64/flutter-sdk-native/usr/share/flutter/sdk)
export PATH="$SDK/bin:$PATH" PUB_CACHE="$SDK/.pub-cache"

cd ~/yocto/meta-local/recipes-flutter/flutter-demo-menu/files/flutter_demo_menu
flutter pub get --offline    # offline works: the SDK ships its own pub cache
flutter analyze
flutter test                 # asserts the UI survives 480x272 through 2048x2048
```

Use the `sysroots-components` path above rather than hunting for the SDK under
`tmp-glibc/work` — `rm_work` deletes work directories, so a `find` there will come up empty
after a clean build.

Then rebuild just what changed:

```bash
cd ~/yocto/build
bitbake -c cleansstate flutter-demo-menu && bitbake mchp-flutter-gallery-image
```

Read `README.md` before designing a UI for this board. The performance constraints are measured,
not guessed, and several ordinary Flutter idioms (gradients, shadows, blur, scaled images) are
5–15× over the per-frame budget.
