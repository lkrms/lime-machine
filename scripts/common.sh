#!/bin/bash

if [ -z "$SCRIPT_DIR" ]; then

    echo "Error: SCRIPT_DIR not defined. Terminating." 1>&2
    exit 1

fi

BACKUP_ROOT=$(cd "$SCRIPT_DIR/.."; pwd)
CONFIG_DIR=$BACKUP_ROOT/config

if [ ! -f "$CONFIG_DIR/settings" ]; then

    echo "Error: $CONFIG_DIR/settings does not exist. Terminating." 1>&2
    exit 1

fi

. "$CONFIG_DIR/settings"

function loggable_time {

    echo -n "[ `date "+%c"` ] "

}

function dump_args {

    echo -e "`loggable_time`Argument(s) passed to $1:\n"

    shift

    ARG_NO=0

    for ARG in "$@"; do

        let "ARG_NO += 1"
        echo "$ARG_NO: $ARG"

    done

    echo -e "\n$ARG_NO argument(s) altogether.\n"

}

function get_targets {

    echo -n `find "$BACKUP_ROOT/targets" -type f \! -iname ".*" \! -iname "README.*"`

}

function check_target {

    TARGET_OK=1

    if [ ! -d "$TARGET_MOUNT_POINT" ]; then

        echo "Invalid mount point for target $TARGET_NAME. Ignoring this target." 1>&2
        TARGET_OK=0

    fi

    if [ $TARGET_MOUNT_CHECK -eq 1 -a `stat --format=%d "$TARGET_MOUNT_POINT"` = `stat --format=%d "$TARGET_MOUNT_POINT/.."` ]; then

        echo "Nothing mounted at $TARGET_MOUNT_POINT for target $TARGET_NAME. Ignoring this target."
        TARGET_OK=0

    fi

}

