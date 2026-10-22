#!/bin/sh
set -eu
# Debian Chromium can crash its network service with an FD ownership violation
# in constrained container builds. Keep Chromium multi-process and disable the
# shared-memory histogram launch path that passes the problematic descriptor.
exec /usr/bin/chromium --disable-features=PassHistogramSharedMemoryOnLaunch "$@"
