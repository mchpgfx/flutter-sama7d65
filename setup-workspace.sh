#!/bin/sh
# Reproduce this Yocto workspace from scratch.
#
# meta-clang and meta-flutter are NOT in the Microchip repo manifest, so their
# revisions are pinned here. Without pinning, a later meta-flutter would silently
# change the Flutter engine version and every app bundle with it.
#
# Run from the directory that should become the workspace root, with meta-local
# already cloned into it:
#
#     mkdir yocto && cd yocto
#     git clone ssh://git@bitbucket.microchip.com/mg/flutter.git meta-local
#     ./meta-local/setup-workspace.sh
#
# Host prerequisites (including the mandatory AppArmor profile on Ubuntu 24.04) are
# in meta-local/BUILDING.md - read that first; BitBake will not run without them.

set -eu

MCHP_TAG="linux4microchip-2026.04"
CLANG_REV="cc29beb210ab94eacc53bbd67e287e4e33ede342"
FLUTTER_REV="719826d2f71076fb616ffea59ee413ad3c62ccba"

command -v repo >/dev/null 2>&1 || {
    echo "error: 'repo' not found. Install it and add to PATH:" >&2
    echo "  mkdir -p ~/bin && curl -sSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo" >&2
    echo "  chmod a+x ~/bin/repo && export PATH=\"\$HOME/bin:\$PATH\"" >&2
    exit 1
}

echo "==> Microchip BSP manifest @ ${MCHP_TAG}"
repo init -u https://github.com/linux4microchip/meta-mchp-manifest.git \
          -b "refs/tags/${MCHP_TAG}" -m mpu/default.xml
repo sync -j8 --no-clone-bundle

# Pinned, not branch-tracked: a moving meta-flutter changes the engine version.
clone_pinned() {
    url="$1"; dir="$2"; branch="$3"; rev="$4"
    if [ -d "$dir/.git" ]; then
        echo "==> $dir exists, checking out $rev"
        git -C "$dir" fetch --quiet origin "$branch"
    else
        echo "==> cloning $dir @ $rev"
        git clone --quiet -b "$branch" "$url" "$dir"
    fi
    git -C "$dir" checkout --quiet "$rev"
}

clone_pinned https://github.com/kraj/meta-clang.git          meta-clang   scarthgap "$CLANG_REV"
clone_pinned https://github.com/meta-flutter/meta-flutter.git meta-flutter scarthgap "$FLUTTER_REV"

cat <<'EOF'

==> Workspace fetched. Now initialise the build:

    export TEMPLATECONF=../meta-local/conf/templates/default
    source openembedded-core/oe-init-build-env build
    bitbake mchp-flutter-gallery-image        # boots into the Flutter demo menu

Full step-by-step instructions, including the mandatory Ubuntu 24.04 AppArmor
profile and how to verify and flash the result: meta-local/BUILDING.md

TEMPLATECONF is only read the first time oe-init-build-env runs for a build
directory; it seeds build/conf/{local,bblayers}.conf from meta-local's template.

TMPDIR/SSTATE_DIR/DL_DIR default to inside build/. A Flutter build wants 80-120 GB
there - override them in build/conf/local.conf if that partition is small. Note
oe-core appends "-glibc", so TMPDIR becomes tmp-glibc on disk.
EOF
