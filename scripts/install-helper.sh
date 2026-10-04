#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo '需要管理员权限' >&2; exit 1; }
[ "$#" = 1 ] && [ -f "$1" ] || exit 1
helper=/Library/PrivilegedHelperTools/dev.switchtool.helper
plist=/Library/LaunchDaemons/dev.switchtool.helper.plist
/bin/mkdir -p /Library/PrivilegedHelperTools
if /bin/launchctl print system/dev.switchtool.helper >/dev/null 2>&1; then
    /bin/launchctl bootout system/dev.switchtool.helper
fi
/usr/bin/install -o root -g wheel -m 755 "$1" "$helper"
/bin/cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.switchtool.helper</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/dev.switchtool.helper</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>5</integer>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$plist"
/bin/chmod 644 "$plist"
/bin/launchctl bootstrap system "$plist"
