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
    TARGET_MAXIMUM_USAGE=
    TARGET_MINIMUM_PURGE_AGE=31536000

    . "$TARGET_FILE"

    check_target || continue

    log_message "Found target volume for $TARGET_NAME at $TARGET_MOUNT_POINT. Initiating snapshot thinning for all sources."

    for SOURCE_ROOT in `find "$TARGET_MOUNT_POINT/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name ".empty" ! -name ".pending" | sort`; do

        log_message "Looking for expired snapshots in $SOURCE_ROOT..."

        PRE_EXPIRED_COUNT=0
        EXPIRED_COUNT=0
        THIN_COUNT=0
        NOW_TIMESTAMP=`now2timestamp`

        # first, pre-expire all but the last snapshot on any given day
        SNAPSHOT_DATES=(`find "$SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][-T][0-9][0-9][0-9][0-9][0-9][0-9]' -exec basename '{}' \; | cut -c 1-10 | sort -u`)

        for SNAPSHOT_DATE in "${SNAPSHOT_DATES[@]}"; do

            SNAPSHOTS=(`find "$SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][-T][0-9][0-9][0-9][0-9][0-9][0-9]' -name "$SNAPSHOT_DATE"'*' -exec basename '{}' \; | sort`)
            SNAPSHOT_COUNT=${#SNAPSHOTS[@]}

            if [ "$SNAPSHOT_COUNT" -gt "1" ]; then

                for ID in $(seq 0 $(( SNAPSHOT_COUNT - 2 ))); do

                    SNAPSHOT=${SNAPSHOTS[$ID]}

                    THIS_DATE=`snapshot2date "$SNAPSHOT"`
                    THIS_TIMESTAMP=`date2timestamp "$THIS_DATE"`
                    THIS_AGE=$(( NOW_TIMESTAMP - THIS_TIMESTAMP ))

                    if [ $THIS_AGE -gt 86400 ]; then

                        SNAPSHOT_ROOT="$SOURCE_ROOT/$SNAPSHOT"
                        SNAPSHOT_NEW_ROOT="$SOURCE_ROOT/.expired.$SNAPSHOT"

                        mv "$SNAPSHOT_ROOT" "$SNAPSHOT_NEW_ROOT"

                        (( PRE_EXPIRED_COUNT++ ))

                    fi

                done

            fi

        done

        SNAPSHOTS=(`find "$SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][-T][0-9][0-9][0-9][0-9][0-9][0-9]' -exec basename '{}' \; | sort`)
        SNAPSHOT_COUNT=${#SNAPSHOTS[@]}
        ACCUM_GAP=0

        SOURCE_NAME="$(basename "$SOURCE_ROOT")"
        SOURCE_FILE="$BACKUP_ROOT/sources/$SOURCE_NAME"

        # identify paths that we always thin (i.e. keep only the latest copy of)
        if [ -f "$SOURCE_FILE" ]; then

            SOURCE_ALWAYS_THIN=()

            . "$SOURCE_FILE"

            if [ "${#SOURCE_ALWAYS_THIN[@]}" -gt "0" ]; then

                shopt -s nullglob

                # don't inspect the most recent snapshot
                for ID in $(seq 0 $(( SNAPSHOT_COUNT - 2 ))); do

                    SNAPSHOT=${SNAPSHOTS[$ID]}

                    for THIN_PATH in "${SOURCE_ALWAYS_THIN[@]}"; do

                        FULL_THIN_GLOB="${SOURCE_ROOT}/${SNAPSHOT}${THIN_PATH}"

                        OLDIFS="$IFS"
                        IFS=$'\n'

                        for FULL_THIN_PATH in $FULL_THIN_GLOB; do

                            if [ -e "$FULL_THIN_PATH" ]; then

                                EXPIRED_SNAPSHOTS=("${EXPIRED_SNAPSHOTS[@]}" "$FULL_THIN_PATH")
                                (( THIN_COUNT++ ))

                            fi

                        done

                        IFS="$OLDIFS"

                    done

                done

                shopt -u nullglob

            fi

        fi

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

        log_message "$SNAPSHOT_COUNT snapshots found after pre-expiring $PRE_EXPIRED_COUNT snapshots. $THIN_COUNT paths identified for removal from within non-current snapshots. $EXPIRED_COUNT snapshots have expired and will be removed."

    done

    # start one subshell per target (fastest processing with minimal hard drive thrashing)
    (
        for SNAPSHOT_ROOT in `find "$TARGET_MOUNT_POINT/snapshots" -mindepth 2 -maxdepth 2 -type d -name '.expired.*' | sort`; do

            log_message "Completing removal of previously expired snapshot at $SNAPSHOT_ROOT..."

            rm -Rf "$SNAPSHOT_ROOT"

        done

        for SNAPSHOT_ROOT in ${EXPIRED_SNAPSHOTS[@]}; do

            log_message "Removing $SNAPSHOT_ROOT..."

            # rename before deleting if this is a full snapshot
            if [ "$(dirname "$SNAPSHOT_ROOT")" == "$SOURCE_ROOT" ]; then

                SNAPSHOT_NEW_ROOT="$(dirname "$SNAPSHOT_ROOT")/.expired.$(basename "$SNAPSHOT_ROOT")"

                mv "$SNAPSHOT_ROOT" "$SNAPSHOT_NEW_ROOT"
                rm -Rf "$SNAPSHOT_NEW_ROOT"

            else

                rm -Rf "$SNAPSHOT_ROOT"

            fi

        done

        log_message "Thinning complete for target $TARGET_NAME."

        if [ -n "$TARGET_MAXIMUM_USAGE" ]; then

            CURRENT_USAGE="$(get_used_space)"
            INITIAL_USAGE="$CURRENT_USAGE"

            if [ "$CURRENT_USAGE" -gt "$TARGET_MAXIMUM_USAGE" ]; then

                log_message "Target $TARGET_NAME is ${CURRENT_USAGE}% full. Removing eligible snapshots until usage is ${TARGET_MAXIMUM_USAGE}% or lower."

                SNAPSHOTS_REMOVED=
                SNAPSHOTS_REMOVED_COUNT=0
                USAGE_RESOLVED=0

                for SNAPSHOT_DATE in $(find "$TARGET_MOUNT_POINT/snapshots" -mindepth 2 -maxdepth 2 -type d -regex '.*/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][-T][0-9][0-9][0-9][0-9][0-9][0-9]' -exec basename '{}' \; | sort | uniq); do

                    THIS_DATE="$(snapshot2date "$SNAPSHOT_DATE")"
                    THIS_TIMESTAMP=$(date2timestamp "$THIS_DATE")
                    NOW_TIMESTAMP=$(now2timestamp)
                    THIS_AGE=$(( NOW_TIMESTAMP - THIS_TIMESTAMP ))

                    # in case percentages / limits have changed since we started
                    . "$TARGET_FILE"

                    if [ "$THIS_AGE" -ge "$TARGET_MINIMUM_PURGE_AGE" ]; then

                        log_message "Removing snapshot(s) with timestamp: $SNAPSHOT_DATE"

                        while read -d $'\0' SNAPSHOT_ROOT; do

                            SNAPSHOTS_REMOVED="${SNAPSHOTS_REMOVED}${SNAPSHOT_ROOT}\n"
                            (( SNAPSHOTS_REMOVED_COUNT++ ))

                            SNAPSHOT_NEW_ROOT="$(dirname "$SNAPSHOT_ROOT")/.expired.$(basename "$SNAPSHOT_ROOT")"

                            mv "$SNAPSHOT_ROOT" "$SNAPSHOT_NEW_ROOT"
                            rm -Rf "$SNAPSHOT_NEW_ROOT"

                        done < <(find "$TARGET_MOUNT_POINT/snapshots" -mindepth 2 -maxdepth 2 -type d -name "$SNAPSHOT_DATE" -print0)

                        CURRENT_USAGE="$(get_used_space)"

                        if [ "$CURRENT_USAGE" -gt "$TARGET_MAXIMUM_USAGE" ]; then

                            log_message "Target $TARGET_NAME is now ${CURRENT_USAGE}% full. Continuing to remove eligible snapshots."

                        else

                            log_message "Target $TARGET_NAME is now ${CURRENT_USAGE}% full. No further snapshots will be removed."
                            USAGE_RESOLVED=1
                            break

                        fi

                    fi

                done

                SUBJECT="target $(hostname -s)/$TARGET_NAME usage is ${CURRENT_USAGE}%"
                MESSAGE="$SNAPSHOTS_REMOVED_COUNT snapshot(s) removed to reduce usage on this target from ${INITIAL_USAGE}% to ${CURRENT_USAGE}%.\n\n"
                NOTIFY="$NOTIFY_EMAIL"

                if [ "$USAGE_RESOLVED" -eq "1" ]; then

                    SUBJECT="Notice: $SUBJECT"

                else

                    SUBJECT="ACTION REQUIRED: $SUBJECT"
                    MESSAGE="${MESSAGE}This usage is higher than the configured maximum of ${TARGET_MAXIMUM_USAGE}%. Further action is therefore required.\n\n"
                    NOTIFY="$ERROR_EMAIL"

                fi

                if [ "$SNAPSHOTS_REMOVED_COUNT" -gt "0" ]; then

                    MESSAGE="${MESSAGE}Snapshots removed:\n\n${SNAPSHOTS_REMOVED}\n"

                fi

                echo -e "$MESSAGE" | mail -s "$SUBJECT" -r "$FROM_EMAIL" "$NOTIFY"

            fi

        fi

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

