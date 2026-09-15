# Bump pseudo to 1.9.11 to fix packaging on modern build hosts.
#
# scarthgap pins pseudo 1.9.0 (28dcefb), which has no openat2() wrapper at all.
# GNU tar 1.35 on glibc 2.39 / kernel 7.x uses openat2(), so pseudo never records
# the resulting directory fd and every do_package task dies with:
#
#   got *at() syscall for unknown directory, fd 4
#   couldn't allocate absolute path for 'include'
#   tar: ./usr/include: Cannot mkdir: Bad address
#
# Upstream fixes: 6533a53 (openat2 wrapper), 125b020 + 9ce8c09 (EFAULT handling),
# bff561c/c63f439 (__open_2/__open64_2), f85e2ae (close_range).
#
# This SRCREV/PV pair is what oe-core master itself ships, so it is the
# upstream-blessed combination rather than an arbitrary bump.
SRCREV = "ba8887e5f1e922f866681ec7dec1a00b602a9328"
PV = "1.9.11"

# Both patches are merged upstream as of this revision (6831273 and 865ca5b),
# so they no longer apply. oe-core master drops them for the same reason,
# while still keeping older-glibc-symbols.patch for native/nativesdk.
SRC_URI:remove = "file://0001-configure-Prune-PIE-flags.patch file://glibc238.patch"

# scarthgap's copy of older-glibc-symbols.patch does not apply to 1.9.11:
# upstream added pseudo_client_scanf.o to the $(LIBPSEUDO) link rule, so the
# Makefile.in hunk's context no longer matches. Ship oe-core master's refreshed
# copy (identical apart from that context) and let it win via FILESEXTRAPATHS.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
