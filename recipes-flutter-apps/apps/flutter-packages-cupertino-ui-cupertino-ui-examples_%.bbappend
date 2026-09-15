# See flutter-samples-material-3-demo_%.bbappend for the full explanation:
# meta-flutter-apps third-party recipes do not set S, but scarthgap`s git fetcher
# unpacks to ${WORKDIR}/git rather than ${WORKDIR}/${BP}, so every task that reads
# the source (do_populate_lic, do_archive_pub_cache, do_compile) fails.
S = "${WORKDIR}/git"
