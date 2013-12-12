#!/bin/bash

# lime-machine: Linux backup software inspired by Time Machine on OS X.
# Copyright (c) 2013 Luke Arms
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

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/common.sh"

EXPIRED_SNAPSHOTS=()

for TARGET_FILE in `get_targets`; do

    TARGET_NAME=`basename "$TARGET_FILE"`
    TARGET_MOUNT_POINT=
    TARGET_MOUNT_CHECK=1

    . "$TARGET_FILE"

    check_target

    if [ $TARGET_OK -eq 0 ]; then

        continue

    fi

    echo "Found target volume for $TARGET_NAME at $TARGET_MOUNT_POINT. Initiating snapshot thinning for all sources."

    for SOURCE_ROOT in `find "$TARGET_MOUNT_POINT/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name ".empty" ! -name ".pending" | sort`; do

        echo "Looking for expired snapshots in $SOURCE_ROOT..."

        SNAPSHOTS=(`find "$SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d -regextype posix-awk -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}[\-T][0-9]{6}' -exec basename '{}' \; | sort`)

        SNAPSHOT_COUNT=${#SNAPSHOTS[@]}
        EXPIRED_COUNT=0
        NOW_TIMESTAMP=`now2timestamp`
        ACCUM_GAP=0

        for ID in `seq 0 $(( SNAPSHOT_COUNT - 1 ))`; do

            SNAPSHOT=${SNAPSHOTS[$ID]}

            THIS_DATE=`snapshot2date "$SNAPSHOT"`
            THIS_TIMESTAMP=`date2timestamp "$THIS_DATE"`

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

                    EXPIRED_SNAPSHOTS+=("$SOURCE_ROOT/$SNAPSHOT")
                    ACCUM_GAP=$THIS_GAP
                    (( EXPIRED_COUNT++ ))

                fi

            fi

            LAST_TIMESTAMP=$THIS_TIMESTAMP

        done

        echo "$SNAPSHOT_COUNT snapshots found. $EXPIRED_COUNT snapshots have expired and will be removed."

    done

done

echo -e "\n\nExpired snapshots: ${#EXPIRED_SNAPSHOTS[@]} in total.\n"

for SNAPSHOT_ROOT in ${EXPIRED_SNAPSHOTS[@]}; do

    echo "Removing $SNAPSHOT_ROOT..."

    echo rm -Rf --one-file-system "$SNAPSHOT_ROOT"

done

