#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/common.sh"

if wget -qP "$BACKUP_ROOT/vss/cygwin/.tmp" "http://cygwin.com/setup-x86.exe" "http://cygwin.com/setup-x86_64.exe"; then

    if ! mv -f "$BACKUP_ROOT/vss/cygwin/.tmp/setup-x86.exe" "$BACKUP_ROOT/vss/cygwin/.tmp/setup-x86_64.exe" "$BACKUP_ROOT/vss/cygwin/"; then

        STATUS=$?

        log_error "Error: unable to move latest version of Cygwin into place. Exit status: $STATUS"
        exit 1

    fi

else

    STATUS=$?

    log_error "Error: unable to retrieve latest version of Cygwin. Exit status: $STATUS"
    exit 1

fi

log_message "Cygwin installers successfully updated."

CYG_PROXY=
CYG_MIRROR=

if [ ! -z "$PROXY_SERVICE" ]; then

    CYG_PROXY="--proxy $PROXY_SERVICE"

fi

if [ ! -z "$CYGWIN_MIRROR" ]; then

    CYG_MIRROR="--site $CYGWIN_MIRROR --only-site"

fi

sed "s/{PROXY}/$CYG_PROXY/g;s/{MIRROR}/$CYG_MIRROR/g;s/{LOCALCACHE}/$CYGWIN_PACKAGE_ROOT/g" $BACKUP_ROOT/vss/install_cygwin.cmd.template > $BACKUP_ROOT/vss/install_cygwin.cmd

log_message "Cygwin installation script updated."

