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

    for SOURCE_ROOT in `find "$TARGET_MOUNT_POINT/snapshots" -mindepth 1 -maxdepth 1 -type d ! -name ".empty" ! -name ".pending"`; do

        echo "Looking for expired snapshots in $SOURCE_ROOT..."

        SNAPSHOTS=`find "$SOURCE_ROOT" -mindepth 1 -maxdepth 1 -type d -regextype posix-awk -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}[\-T][0-9]{6}' -exec basename '{}' \; | sort`

    done

done
