#!/bin/bash

if [ -z "$SCRIPT_DIR" ]; then

    echo "Error: SCRIPT_DIR not defined. Terminating." 1>&2
    exit 1

fi

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"

BACKUP_ROOT="$(cd "$SCRIPT_DIR/.."; pwd -P)"
CONFIG_DIR="$BACKUP_ROOT/config"
SCRIPT_NAME="$(basename "$0")"
BASH_MAJOR_VERSION="${BASH_VERSINFO[0]}"

if [ ! -f "$CONFIG_DIR/settings" ]; then

    echo "Error: $CONFIG_DIR/settings does not exist. Terminating." 1>&2
    exit 1

fi

SEQUENTIAL_OPERATIONS=0

. "$CONFIG_DIR/settings"

mkdir -p "$(dirname "$LOG_FILE")" || { echo "Error: $(dirname "$LOG_FILE") doesn't exist."; exit 1; }
touch "$LOG_FILE" || { echo "Error: unable to open $LOG_FILE for writing."; exit 1; }

mkdir -p "$RUN_DIR" || { echo "Error: $RUN_DIR doesn't exist."; exit 1; }
[ -w "$RUN_DIR" ] || { echo "Error: unable to write to $RUN_DIR."; exit 1; }

if [ ! -z "$PROXY_SERVICE" ]; then

    export http_proxy="http://$PROXY_SERVICE"
    export https_proxy="$http_proxy"

fi

ERROR_LOG=""

function log_error {

    # don't output to stderr unless we're on a tty
    tty -s && echo -e "$@" >&2

    local THIS_ERROR
    THIS_ERROR="$(log_time) $@"

    echo -e "$THIS_ERROR" >> "$LOG_FILE"
    ERROR_LOG="${ERROR_LOG}${THIS_ERROR}\n"

}

function send_error_log {

    if [ ! -z "$ERROR_LOG" ]; then

        local SUBJECT
        local MESSAGE
        SUBJECT="WARNING: Backup errors reported on $(hostname -s)"
        MESSAGE="Relevant log entries follow.\n\n$ERROR_LOG\n"

        echo -e "$MESSAGE" | mail -s "$SUBJECT" -r "$FROM_EMAIL" "$ERROR_EMAIL"

    fi

}

trap "send_error_log" EXIT

function log_message {

    # don't output to stdout unless we're on a tty
    tty -s && echo -e "$@"

    echo -e "$(log_time) $@" >> "$LOG_FILE"

}

function log_source {

    echo -e "$(log_time) $@" >> "$SOURCE_LOG_FILE"

}

function escape_for_sed {

    echo "$@" | sed 's/[\/&]/\\&/g'

}

function snapshot2date {

    echo "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}"

}

function date2timestamp {

    date -d "$1" "+%s"

}

function now2timestamp {

    date "+%s"

}

function log_time {

    date "+%b %d %T"

}

function dump_args {

    echo -e "Argument(s) passed to $1:\n"

    shift

    ARG_NO=0

    for ARG in "$@"; do

        (( ARG_NO++ ))
        echo "$ARG_NO: $ARG"

    done

    echo -e "\n$ARG_NO argument(s) altogether.\n"

}

function get_targets {

    find "$BACKUP_ROOT/targets" -type f ! -iname '.*' ! -iname '*.inactive' ! -iname 'README.*' -print0 | sort -z

}

function close_targets {

    # allow time for any pending file locks to be released
    sleep 30

    # no backgrounding, because this may be called pre-shutdown
    while read -d $'\0' TARGET_FILE; do

        TARGET_NAME="$(basename "$TARGET_FILE")"
        TARGET_MOUNT_POINT=
        TARGET_MOUNT_CHECK=1
        TARGET_ATTEMPT_MOUNT=0
        TARGET_UNMOUNT=0

        . "$TARGET_FILE"

        check_target >/dev/null 2>&1 || continue

        # compress log files more than 2 days old
        find "$TARGET_MOUNT_POINT/logs" -type f -name '*.log' -mtime +2 -exec gzip '{}' \;

        if [ "$TARGET_UNMOUNT" -eq "1" ]; then

            if ! umount "$TARGET_MOUNT_POINT"; then

                log_error "Unable to unmount filesystem at $TARGET_MOUNT_POINT for target $TARGET_NAME."

            fi

        fi

    done < <(get_targets)

}

function check_target {

    if [ -z "$TARGET_MOUNT_POINT" ]; then

        log_error "No mount point defined for target $TARGET_NAME. Ignoring this target."
        return 1

    fi

    if [ ! -d "$TARGET_MOUNT_POINT" ]; then

        log_error "Invalid mount point for target $TARGET_NAME. Ignoring this target."
        return 1

    fi

    if [ "$TARGET_MOUNT_CHECK" -eq "1" -a "$(stat --format=%d "$TARGET_MOUNT_POINT")" = "$(stat --format=%d "$TARGET_MOUNT_POINT/..")" ]; then

        if [ "$TARGET_ATTEMPT_MOUNT" -eq "1" ]; then

            if ! mount "$TARGET_MOUNT_POINT"; then

                log_message "Unable to mount a filesystem at $TARGET_MOUNT_POINT for target $TARGET_NAME. Ignoring this target."
                return 1

            fi

        else

            log_message "Nothing mounted at $TARGET_MOUNT_POINT for target $TARGET_NAME. Ignoring this target."
            return 1

        fi

    fi

    return 0

}

function get_sources {

    find "$BACKUP_ROOT/active-sources" \( -type f -o -type l \) ! -iname '.*' ! -iname 'README.*' -print0 | sort -z

}

function get_used_space {

    df "$TARGET_MOUNT_POINT" | tail -1 | awk '{print $5}' | sed 's/[^0-9]//g'

}

