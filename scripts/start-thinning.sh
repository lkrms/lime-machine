#!/bin/bash

# lime-machine: Linux backup software inspired by Time Machine on OS X.
# Copyright (c) 2013-2018 Luke Arms
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

trap "" SIGHUP

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/common.sh"

# exit without error if another instance is already running
if pidof -x -o $$ -o $PPID "$(basename "$0")" >/dev/null; then

  log_message "Snapshot thinning is already in progress. Ignoring request to start thinning."
  exit 0

fi

EXPIRED_TOTAL=0

for TARGET_FILE in `get_targets`; do

    EXPIRED_SNAPSHOTS=()

    TARGET_NAME=`basename "$TARGET_FILE"`
    TARGET_MOUNT_POINT=
    TARGET_MOUNT_CHECK=1
    TARGET_ATTEMPT_MOUNT=0
    TARGET_UNMOUNT=0

    . "$TARGET_FILE"

    check_target || continue

    log_message "Found target volume for $TARGET_NAME at $TARGET_MOUNT_POINT. Initiating snapshot thinning for all sources."

    for SOURCE_ROOT in `find "$TARGET_MOUNT_POINT/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name ".empty" ! -name ".pending" | sort`; do

        log_message "Looking for expired snapshots in $SOURCE_ROOT..."

        SNAPSHOTS=(`find "$SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][-T][0-9][0-9][0-9][0-9][0-9][0-9]' -exec basename '{}' \; | sort`)

        SNAPSHOT_COUNT=${#SNAPSHOTS[@]}
        EXPIRED_COUNT=0
        NOW_TIMESTAMP=`now2timestamp`
        ACCUM_GAP=0

        # TODO: auto-expire all but last snapshot for each day beyond yesterday

        for ID in `seq 0 $(( SNAPSHOT_COUNT - 1 ))`; do

            SNAPSHOT=${SNAPSHOTS[$ID]}

            THIS_DATE=`snapshot2date "$SNAPSHOT"`
            THIS_TIMESTAMP=`date2timestamp "$THIS_DATE"`

            # only proceed if this isn't the first or last snapshot
            if [ $ID -gt 0 -a $(( ID + 1 )) -lt $SNAPSHOT_COUNT ]; then

                THIS_AGE=$(( NOW_TIMESTAMP - THIS_TIMESTAMP ))

                # these MAX_GAP values factor in a 5% tolerance for variation in snapshot times
                if [ $THIS_AGE -le 86400 ]; then

                    # if age <= 24 hours, keep hourlies
                    MAX_GAP=3780

                elif [ $THIS_AGE -le 2419200 ]; then

                    # if age <= 28 days, keep dailies
                    MAX_GAP=90720

                else

                    # otherwise, keep weeklies
                    MAX_GAP=635040

                fi

                THIS_GAP=$(( THIS_TIMESTAMP - LAST_TIMESTAMP + ACCUM_GAP ))
                ACCUM_GAP=0

                NEXT_GAP=$(( $(date2timestamp "$(snapshot2date "${SNAPSHOTS[$(( ID + 1 ))]}")") - THIS_TIMESTAMP ))

                # This snapshot is considered expired if:
                #
                # (1) the seconds elapsed ("gap") since the previous snapshot is less than MAX_GAP; and
                # (2) the NEXT snapshot's "gap" will still be less than MAX_GAP after deleting it.
                #
                # Because (2) implies (1), this is a very simple test.
                #
                if [ $(( THIS_GAP + NEXT_GAP )) -lt $MAX_GAP ]; then

                    EXPIRED_SNAPSHOTS=("${EXPIRED_SNAPSHOTS[@]}" "$SOURCE_ROOT/$SNAPSHOT")
                    ACCUM_GAP=$THIS_GAP
                    (( EXPIRED_COUNT++ ))
                    (( EXPIRED_TOTAL++ ))

                fi

            fi

            LAST_TIMESTAMP=$THIS_TIMESTAMP

        done

        log_message "$SNAPSHOT_COUNT snapshots found. $EXPIRED_COUNT snapshots have expired and will be removed..."

    done

    # start one subshell per target (fastest processing with minimal hard drive thrashing)
    (
        for SNAPSHOT_ROOT in ${EXPIRED_SNAPSHOTS[@]}; do

            log_message "Removing $SNAPSHOT_ROOT..."

            SNAPSHOT_NEW_ROOT=$(dirname "$SNAPSHOT_ROOT")/.expired.$(basename "$SNAPSHOT_ROOT")

            mv "$SNAPSHOT_ROOT" "$SNAPSHOT_NEW_ROOT"
            rm -Rf "$SNAPSHOT_NEW_ROOT"

        done

        for SNAPSHOT_ROOT in `find "$TARGET_MOUNT_POINT/snapshots" -mindepth 2 -maxdepth 2 -type d -name '.expired.*' | sort`; do

            log_message "Completing removal of previously expired snapshot at $SNAPSHOT_ROOT..."

            rm -Rf "$SNAPSHOT_ROOT"

        done

        log_message "Thinning complete for target $TARGET_NAME."
    ) &

done

if [ -z "$LIME_MACHINE_SHUTDOWN_PENDING" ]; then

    LIME_MACHINE_SHUTDOWN_PENDING=0

fi

if [ $LIME_MACHINE_SHUTDOWN_PENDING -eq 1 ]; then

    log_message "Shutdown pending. Waiting for snapshot thinning to complete on all volumes."

    wait

    log_message "Snapshot thinning complete. Shutting down."

    close_targets

    $SHUTDOWN_COMMAND

else

    wait

    log_message "Snapshot thinning complete."

    close_targets

fi

