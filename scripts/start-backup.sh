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

EXCLUDE_PATH=$CONFIG_DIR/exclude.always

if [ ! -f "$EXCLUDE_PATH" ]; then

	touch "$EXCLUDE_PATH"

	if [ $? -ne 0 ]; then

		echo "Error: $EXCLUDE_PATH does not exist. Terminating." 1>&2
		exit 1

	else

		echo "Warning: $EXCLUDE_PATH did not exist, so it was created without content." 1>&2

	fi

fi

function do_rsync {

	# just in case huponexit is on
	trap "" HUP

	local SOURCE=$1; shift
	local OPTIONS=("$@")

	# properly handle the possibility that RSYNC_OPTIONS isn't an array
	if [ `declare -p RSYNC_OPTIONS 2>/dev/null | grep -q '^declare \-a'; echo $?` -eq 0 ]; then

		# another possibility is that someone tried to clear RSYNC_OPTIONS by assigning an empty string
		if [ ${#RSYNC_OPTIONS[*]} -ge 1 -a -n "${RSYNC_OPTIONS[0]}" ]; then

			OPTIONS+=("${RSYNC_OPTIONS[@]}")

		fi

	else

	    # the lack of quoting is deliberate; we want arguments to be separated
	    OPTIONS+=($RSYNC_OPTIONS)

	fi

	if [ ! -z "$SOURCE_SECRET" ]; then

		OPTIONS+=(--password-file "$SOURCE_SECRET")

	fi

	if [ ! -z "$SOURCE_EXCLUDE" ]; then

		OPTIONS+=(--exclude-from "$SOURCE_EXCLUDE")

	fi

	dump_args rsync -lrtOv --no-p --no-g --chmod=ugo=rwX "${OPTIONS[@]}" --exclude-from "$EXCLUDE_PATH" --link-dest="$TARGET_MOUNT_POINT/latest/$SOURCE_NAME/" "$SOURCE" "$PENDING_TARGET/"

	echo -e "`loggable_time`Starting rsync now. stdout:\n" >> "$LOG_FILE"

	rsync -lrtOv --no-p --no-g --chmod=ugo=rwX "${OPTIONS[@]}" --exclude-from "$EXCLUDE_PATH" --link-dest="$TARGET_MOUNT_POINT/latest/$SOURCE_NAME/" "$SOURCE" "$PENDING_TARGET/" >> "$LOG_FILE" 2>$TEMP_FILE

	STATUS=$?
	ERR=`< $TEMP_FILE`

	echo -e "\n\n`loggable_time`Returned from rsync. stderr:\n\n$ERR\n\nExit status: $STATUS\n" >> "$LOG_FILE"

	if [ $STATUS -eq 0 ]; then

		SUCCESS=1
		SUBJECT="Success: $SUBJECT"
		MESSAGE="No errors were reported.\n\nSee $LOG_FILE on `hostname -s` for more information."

	elif [ $STATUS -eq 23 -o $STATUS -eq 24 ]; then

		SUCCESS=1
		SUBJECT="Success (partial transfer): $SUBJECT"
		MESSAGE="Partial transfer reported (exit status: $STATUS).\n\nOutput collected from stderr is below. See $LOG_FILE on `hostname -s` for more information.\n\n$ERR"

	else

		SUBJECT="FAILURE: $SUBJECT"
		MESSAGE="Exit status: $STATUS.\n\nOutput collected from stderr is below. See $LOG_FILE on `hostname -s` for more information.\n\nNOTE: $PENDING_TARGET will not be cleaned up automatically.\n\n$ERR"

	fi

	do_finalise

}

function do_mysql {

	trap "" HUP

	local OPTIONS=()

	if [ `declare -p MYSQLDUMP_OPTIONS 2>/dev/null | grep -q '^declare \-a'; echo $?` -eq 0 ]; then

		if [ ${#MYSQLDUMP_OPTIONS[*]} -ge 1 -a -n "${MYSQLDUMP_OPTIONS[0]}" ]; then

			OPTIONS+=("${MYSQLDUMP_OPTIONS[@]}")

		fi

	else

	    OPTIONS+=($MYSQLDUMP_OPTIONS)

	fi

	SUCCESS=1

	echo -e "`loggable_time`Retrieving list of databases.\n" >> "$LOG_FILE"

	SOURCE_DB_LIST=`mysql --host="$SOURCE_HOST" --user="$SOURCE_USER" --password="$SOURCE_PASSWORD" --batch --skip-column-names --execute="show databases" 2>$TEMP_FILE | grep -v "^\(mysql\|information_schema\|test\)\$"`

	STATUS=$?
	ERR=`< $TEMP_FILE`

	echo -e "`loggable_time`Returned from mysql. stderr:\n\n$ERR\n\nExit status: $STATUS\n" >> "$LOG_FILE"

	if [ $STATUS -ne 0 ]; then

		SUCCESS=0
		SOURCE_DB_LIST=

	else

		echo -e "Databases discovered:\n\n$SOURCE_DB_LIST\n" >> "$LOG_FILE"

		ERR=

		for SOURCE_DB in $SOURCE_DB_LIST; do

			dump_args mysqldump --host="$SOURCE_HOST" --user="$SOURCE_USER" --password="$SOURCE_PASSWORD" "${OPTIONS[@]}" "$SOURCE_DB"

			echo -e "`loggable_time`Starting mysqldump now.\n" >> "$LOG_FILE"

			mysqldump --host="$SOURCE_HOST" --user="$SOURCE_USER" --password="$SOURCE_PASSWORD" "${OPTIONS[@]}" "$SOURCE_DB" 2>$TEMP_FILE | gzip > "$PENDING_TARGET/${SOURCE_DB}_${DATE}.sql.gz"

			STATUS=${PIPESTATUS[0]}
			THIS_ERR=`< $TEMP_FILE`

			echo -e "`loggable_time`Returned from mysqldump. stderr:\n\n$THIS_ERR\n\nExit status: $STATUS\n" >> "$LOG_FILE"

			if [ $STATUS -ne 0 ]; then

				SUCCESS=0
				ERR="${ERR}stderr output for $SOURCE_DB (exit status $STATUS):\n$THIS_ERR\n\n"

			fi

		done

	fi

	MESSAGE="Databases discovered:\n$SOURCE_DB_LIST\n\n"

	if [ $SUCCESS -eq 0 ]; then

		SUBJECT="FAILURE: $SUBJECT"
		MESSAGE="One or more MySQL backup operations failed. Output collected from stderr is below.\n\nNOTE: $PENDING_TARGET will not be cleaned up automatically.\n\n${MESSAGE}${ERR}"

	else

		SUBJECT="Success: $SUBJECT"
		MESSAGE="No errors were reported.\n\n${MESSAGE}"

	fi

	do_finalise

}

function do_postgres {

	trap "" HUP

	export PGPASSFILE=`mktemp`
	echo "*:*:*:*:$SOURCE_PASSWORD" > $PGPASSFILE

	dump_args pg_dumpall --host="$SOURCE_HOST" --port=$SOURCE_PORT --username="$SOURCE_USER" --no-password

	echo -e "`loggable_time`Starting pg_dumpall now.\n" >> "$LOG_FILE"

	pg_dumpall --host="$SOURCE_HOST" --port=$SOURCE_PORT --username="$SOURCE_USER" --no-password 2>$TEMP_FILE | gzip > "$PENDING_TARGET/all_databases_${DATE}.sql.gz"

	STATUS=${PIPESTATUS[0]}
	ERR=`< $TEMP_FILE`

	echo -e "`loggable_time`Returned from pg_dumpall. stderr:\n\n$ERR\n\nExit status: $STATUS\n" >> "$LOG_FILE"

	rm $PGPASSFILE

	if [ $STATUS -ne 0 ]; then

		SUCCESS=0
		SUBJECT="FAILURE: $SUBJECT"
		MESSAGE="Exit status: $STATUS.\n\nOutput collected from stderr is below. See $LOG_FILE on `hostname -s` for more information.\n\nNOTE: $PENDING_TARGET will not be cleaned up automatically.\n\n$ERR"

	else

		SUCCESS=1
		SUBJECT="Success: $SUBJECT"
		MESSAGE="No errors were reported.\n\nSee $LOG_FILE on `hostname -s` for more information."

	fi

	do_finalise

}

function do_finalise {

	if [ $SUCCESS -eq 1 ]; then

		RESULT="SUCCEEDED"

	else

		RESULT="FAILED"

	fi

	echo -e "`loggable_time`Backup operation: $RESULT\n" >> "$LOG_FILE"

	echo -e "$MESSAGE" | mail -s "$SUBJECT" "$NOTIFY_EMAIL"

	echo -e "`loggable_time`Result notification sent:\n\nTo: $NOTIFY_EMAIL\nSubject: $SUBJECT\nMessage:\n$MESSAGE.\n" >> "$LOG_FILE"

	if [ $SUCCESS -eq 1 ]; then

		mv "$PENDING_TARGET" "$TARGET_MOUNT_POINT/snapshots/$SOURCE_NAME"
		rm -f "$TARGET_MOUNT_POINT/latest/$SOURCE_NAME"
		ln -s "$TARGET_MOUNT_POINT/snapshots/$SOURCE_NAME/$DATE" "$TARGET_MOUNT_POINT/latest/$SOURCE_NAME"

		echo -e "`loggable_time`Snapshot moved from 'pending' to 'latest'.\n" >> "$LOG_FILE"

		if [ $SOURCE_TYPE = "rsync_shadow" ]; then

			echo -e "`loggable_time`Closing shadow copy.\n" >> "$LOG_FILE"

			ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i "$SSH_KEY" "$SSH_USER@$SOURCE_HOST" "//`hostname -s`/vss/close_copy.cmd $SHADOW_PATH $DATE" > $TEMP_FILE 2>&1

			STATUS=$?
			ERR=`< $TEMP_FILE`

			echo -e "`loggable_time`Returned from close_copy.cmd. Output:\n\n$ERR\n\nExit status: $STATUS\n" >> "$LOG_FILE"

			if [ $STATUS -ne 0 ]; then

				SUBJECT="WARNING: $SUBJECT"
				MESSAGE="Unable to close shadow copy. Exit status: $STATUS.\n\nOutput collected from stderr is below.\n\n$ERR"

				echo -e "$MESSAGE" | mail -s "$SUBJECT" "$NOTIFY_EMAIL"

				echo -e "`loggable_time`Error notification sent:\n\nTo: $NOTIFY_EMAIL\nSubject: $SUBJECT\nMessage:\n$MESSAGE.\n" >> "$LOG_FILE"

			fi

		fi

	fi

	rm $TEMP_FILE

}

function loggable_time {

	echo -n "[ `date "+%c"` ] "

}

function dump_args {

	echo -e "`loggable_time`Argument(s) passed to $1:\n" >> "$LOG_FILE"

	shift

	ARG_NO=0

	for ARG in "$@"; do

		let "ARG_NO += 1"
		echo "$ARG_NO: $ARG" >> "$LOG_FILE"

	done

	echo -e "\n$ARG_NO argument(s) altogether.\n" >> "$LOG_FILE"

}

for TARGET_FILE in `find "$BACKUP_ROOT/targets" -type f \! -iname ".*" \! -iname "README.*"`; do

	TARGET_NAME=`basename "$TARGET_FILE"`
	TARGET_MOUNT_POINT=
	TARGET_MOUNT_CHECK=1

	. "$TARGET_FILE"

	if [ ! -d "$TARGET_MOUNT_POINT" ]; then

		echo "Invalid mount point for target $TARGET_NAME. Ignoring this target." 1>&2
		continue

	fi

	if [ $TARGET_MOUNT_CHECK -eq 1 -a `stat --format=%d "$TARGET_MOUNT_POINT"` = `stat --format=%d "$TARGET_MOUNT_POINT/.."` ]; then

		echo "Nothing mounted at $TARGET_MOUNT_POINT for target $TARGET_NAME. Ignoring this target."
		continue

	fi

	echo "Found target volume for $TARGET_NAME at $TARGET_MOUNT_POINT. Initiating backup sequence."

	mkdir -p "$TARGET_MOUNT_POINT/snapshots/.empty"
	mkdir -p "$TARGET_MOUNT_POINT/snapshots/.pending"
	mkdir -p "$TARGET_MOUNT_POINT/latest"
	mkdir -p "$TARGET_MOUNT_POINT/logs"

	if [ $# -gt 0 ]; then

		SOURCE_FILES=$@

	else

		SOURCE_FILES=`find "$BACKUP_ROOT/active-sources" \( -type f -o -type l \) \! -iname ".*" \! -iname "README.*"`

	fi

	for SOURCE_FILE in $SOURCE_FILES; do

		if [ ! -f "$SOURCE_FILE" ]; then

			SOURCE_FILE="$BACKUP_ROOT/sources/$SOURCE_FILE"

			if [ ! -f "$SOURCE_FILE" ]; then

				echo "Unable to find source file $SOURCE_FILE. Ignoring this source." 1>&2
				continue

			fi

		fi

		SOURCE_NAME=`basename "$SOURCE_FILE"`

		SOURCE_TYPE=
		SOURCE_HOST=
		SOURCE_PATH=
		SOURCE_USER=
		SOURCE_SECRET=
		SOURCE_PASSWORD=
		SOURCE_EXCLUDE=
		SOURCE_PORT=
		SSH_USER=
		SSH_PORT=
		SSH_KEY=
		SHADOW_PATH=
		SHADOW_VOLUMES=
		RSYNC_OPTIONS=()
		MYSQLDUMP_OPTIONS=()

		. "$SOURCE_FILE"

		mkdir -p "$TARGET_MOUNT_POINT/snapshots/$SOURCE_NAME"
		mkdir -p "$TARGET_MOUNT_POINT/snapshots/.pending/$SOURCE_NAME"
		mkdir -p "$TARGET_MOUNT_POINT/logs/$SOURCE_NAME"

		if [ ! -h "$TARGET_MOUNT_POINT/latest/$SOURCE_NAME" ]; then

			# if this is the first backup of this source to this target, link its "latest" snapshot to an empty folder
			ln -fs "$TARGET_MOUNT_POINT/snapshots/.empty" "$TARGET_MOUNT_POINT/latest/$SOURCE_NAME"

		fi

		DATE=`date "+%Y-%m-%d-%H%M%S"`
		SUCCESS=0
		SUBJECT="backup of $SOURCE_NAME to `hostname -s`/$TARGET_NAME [ref: $DATE]"
		MESSAGE=

		LOG_FILE="$TARGET_MOUNT_POINT/logs/$SOURCE_NAME/$SOURCE_NAME-$DATE.log"
		TEMP_FILE=`mktemp`
		PENDING_TARGET="$TARGET_MOUNT_POINT/snapshots/.pending/$SOURCE_NAME/$DATE"

		echo -e "`loggable_time`Backup operation commencing. Environment:\n\n`printenv`\n" >> "$LOG_FILE"

		mkdir -p "$PENDING_TARGET"

		echo -e "`loggable_time`Target directory created.\n" >> "$LOG_FILE"

		case $SOURCE_TYPE in

			rsync)

				echo "Attempting rsync backup of '$SOURCE_NAME' to '$TARGET_NAME'..."

				(do_rsync $SOURCE_USER@$SOURCE_HOST::"$SOURCE_PATH/" --copy-unsafe-links &)

				;;

			rsync_ssh)

				echo "Attempting rsync backup of '$SOURCE_NAME' to '$TARGET_NAME' over SSH..."

				(do_rsync $SSH_USER@$SOURCE_HOST:"$SOURCE_PATH/" --copy-unsafe-links -e "ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i '$SSH_KEY'" &)

				;;

			rsync_shadow)

				echo "Attempting rsync backup of '$SOURCE_NAME' to '$TARGET_NAME' with shadow copy..."

				echo -e "`loggable_time`Creating shadow copy.\n" >> "$LOG_FILE"

				ssh -o StrictHostKeyChecking=no -p $SSH_PORT -i "$SSH_KEY" "$SSH_USER@$SOURCE_HOST" "//`hostname -s`/vss/create_copy.cmd $SHADOW_PATH $DATE $SHADOW_VOLUMES" > $TEMP_FILE 2>&1

				STATUS=$?
				ERR=`< $TEMP_FILE`

				echo -e "`loggable_time`Returned from create_copy.cmd. Output:\n\n$ERR\n\nExit status: $STATUS\n" >> "$LOG_FILE"

				if [ $STATUS -ne 0 ]; then

					SUBJECT="FAILURE: $SUBJECT"
					MESSAGE="Unable to create shadow copy. Exit status: $STATUS.\n\nOutput collected from stderr is below.\n\n$ERR"
					do_finalise

				else

					# allow shadow copy to "settle"
					sleep 5

					(do_rsync $SOURCE_USER@$SOURCE_HOST::"$SOURCE_PATH/$DATE/" --safe-links &)

				fi

				;;

			mysql)

				echo "Attempting MySQL backup of '$SOURCE_NAME' to '$TARGET_NAME'..."

				(do_mysql &)

				;;

			postgres)

				echo "Attempting PostgreSQL backup of '$SOURCE_NAME' to '$TARGET_NAME'..."

				(do_postgres &)

				;;

			*)

				echo "Invalid source type for '$SOURCE_NAME'. Ignoring this source." 1>&2

				;;

		esac

	done

done

