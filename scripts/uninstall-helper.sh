#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '请使用 sudo 执行' >&2; exit 1; }
# SIGTERM requests adapter restoration before shutdown.
/bin/launchctl bootout system/dev.switchtool.helper
/bin/rm -f /Library/LaunchDaemons/dev.switchtool.helper.plist /Library/PrivilegedHelperTools/dev.switchtool.helper /var/run/dev.switchtool.socket
