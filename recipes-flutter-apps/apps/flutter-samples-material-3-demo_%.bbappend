# Point S at where the git fetcher actually unpacks.
#
# The meta-flutter-apps third-party recipes (174 of 220) never set S, relying on
# newer oe-core lining up the git fetcher's destination with the default
# S = ${WORKDIR}/${BP} via BB_GIT_DEFAULT_DESTSUFFIX. Scarthgap's bitbake has no
# such variable: git unpacks to ${WORKDIR}/git, so S points at a directory that
# does not exist and every task that reads the source fails:
#
#   do_populate_lic:  LIC_FILES_CHKSUM points to an invalid file:
#                     .../<pn>-<pv>/LICENSE   (Errno 2)
#   do_archive_pub_cache: assert Path(directory).is_dir()  -> AssertionError
#
# meta-flutter's own ivi-homescreen-test.inc documents this exact trap and sets S
# explicitly for the same reason; the third-party app recipes simply were not
# given the same treatment.
#
# Not fixable globally: BB_GIT_DEFAULT_DESTSUFFIX would change the unpack
# destination for EVERY git recipe in the build, breaking the many that already
# set S = "${WORKDIR}/git" on purpose (pseudo, ivi-homescreen, dt-overlay-mchp...).
# So it is one bbappend per app we actually want.
S = "${WORKDIR}/git"
