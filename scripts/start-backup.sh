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

trap "" SIGHUP

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_DIR/common.sh"

EXCLUDE_PATH=$CONFIG_DIR/exclude.always

if [ ! -f "$EXCLUDE_PATH" ]; then

	if ! touch "$EXCLUDE_PATH"; then

		echo "Error: $EXCLUDE_PATH does not exist. Terminating." 1>&2
		exit 1

	else

		echo "Warning: $EXCLUDE_PATH did not exist, so it was created without content." 1>&2

	fi

fi

sed "s/{HOSTNAME}/$(hostname -s)/g" $BACKUP_ROOT/vss/.create_copy.cmd.template > $BACKUP_ROOT/vss/create_copy.cmd

function do_rsync {

	local SOURCE
	local OPTIONS

	SOURCE=$1; shift
	OPTIONS=("$@")

	# properly handle the possibility that RSYNC_OPTIONS isn't an array
	if declare -p RSYNC_OPTIONS 2>/dev/null | grep -q '^declare \-a'; then

		# another possibility is that someone tried to clear RSYNC_OPTIONS by assigning an empty string
		if [ ${#RSYNC_OPTIONS[*]} -ge 1 -a -n "${RSYNC_OPTIONS[0]}" ]; then

			OPTIONS=("${OPTIONS[@]}" "${RSYNC_OPTIONS[@]}")

		fi

	else

	    # the lack of quoting is deliberate; we want arguments to be separated
	    OPTIONS=("${OPTIONS[@]}" $RSYNC_OPTIONS)

	fi

	if [ ! -z "$SOURCE_SECRET" ]; then

		OPTIONS=("${OPTIONS[@]}" --password-file "$SOURCE_SECRET")

	fi

	if [ ! -z "$SOURCE_EXCLUDE" ]; then

		OPTIONS=("${OPTIONS[@]}" --exclude-from "$SOURCE_EXCLUDE")

	fi

	log_source "$(dump_args rsync -lrtOv --no-p --no-g --chmod=ugo=rwX "${OPTIONS[@]}" --exclude-from "$EXCLUDE_PATH" --link-dest="$TARGET_MOUNT_POINT/latest/$SOURCE_NAME/" "$SOURCE" "$PENDING_TARGET/")"

	log_source "Starting rsync now. stdout:\n"

	rsync -lrtOv --no-p --no-g --chmod=ugo=rwX "${OPTIONS[@]}" --exclude-from "$EXCLUDE_PATH" --link-dest="$TARGET_MOUNT_POINT/latest/$SOURCE_NAME/" "$SOURCE" "$PENDING_TARGET/" >> "$SOURCE_LOG_FILE" 2>$TEMP_FILE

	STATUS=$?
	ERR=`< $TEMP_FILE`

	log_source "Returned from rsync. stderr:\n\n$ERR\n\nExit status: $STATUS\n"

	if [ $STATUS -eq 0 ]; then

		SUCCESS=1
		SUBJECT="Success: $SUBJECT"
		MESSAGE="No errors were reported.\n\nSee $SOURCE_LOG_FILE on `hostname -s` for more information."

	elif [ $STATUS -eq 23 -o $STATUS -eq 24 ]; then

		SUCCESS=1
		SUBJECT="Success (partial transfer): $SUBJECT"
		MESSAGE="Partial transfer reported (exit status: $STATUS).\n\nOutput collected from stderr is below. See $SOURCE_LOG_FILE on `hostname -s` for more information.\n\n$ERR"

	else

		SUBJECT="FAILURE: $SUBJECT"
		MESSAGE="Exit status: $STATUS.\n\nOutput collected from stderr is below. See $SOURCE_LOG_FILE on `hostname -s` for more information.\n\nNOTE: $PENDING_TARGET will not be cleaned up automatically.\n\n$ERR"

	fi

	do_finalise

}

function do_mysql {

	local OPTIONS
	OPTIONS=()

	if declare -p MYSQLDUMP_OPTIONS 2>/dev/null | grep -q '^declare \-a'; then

		if [ ${#MYSQLDUMP_OPTIONS[*]} -ge 1 -a -n "${MYSQLDUMP_OPTIONS[0]}" ]; then

			OPTIONS=("${OPTIONS[@]}" "${MYSQLDUMP_OPTIONS[@]}")

		fi

	else

	    OPTIONS=("${OPTIONS[@]}" $MYSQLDUMP_OPTIONS)

	fi

	SUCCESS=1

	log_source "Retrieving list of databases."

	SOURCE_DB_LIST=`mysql --host="$SOURCE_HOST" --user="$SOURCE_USER" --password="$SOURCE_PASSWORD" --batch --skip-column-names --execute="show databases" 2>$TEMP_FILE | grep -v "^\(mysql\|information_schema\|test\)\$"`

	STATUS=$?
	ERR=`< $TEMP_FILE`

	log_source "Returned from mysql. stderr:\n\n$ERR\n\nExit status: $STATUS\n"

	if [ $STATUS -ne 0 ]; then

		SUCCESS=0
		SOURCE_DB_LIST=

	else

		log_source "Databases discovered:\n\n$SOURCE_DB_LIST\n"

		ERR=

		for SOURCE_DB in $SOURCE_DB_LIST; do

			log_source "$(dump_args mysqldump --host="$SOURCE_HOST" --user="$SOURCE_USER" --password="$SOURCE_PASSWORD" "${OPTIONS[@]}" "$SOURCE_DB")"

			log_source "Starting mysqldump now."

			mysqldump --host="$SOURCE_HOST" --user="$SOURCE_USER" --password="$SOURCE_PASSWORD" "${OPTIONS[@]}" "$SOURCE_DB" 2>$TEMP_FILE | gzip > "$PENDING_TARGET/${SOURCE_DB}_${DATE}.sql.gz"

			STATUS=${PIPESTATUS[0]}
			THIS_ERR=`< $TEMP_FILE`

			log_source "Returned from mysqldump. stderr:\n\n$THIS_ERR\n\nExit status: $STATUS\n"

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

	export PGPASSFILE=`mktemp`
	echo "*:*:*:*:$SOURCE_PASSWORD" > $PGPASSFILE

	log_source $(dump_args pg_dumpall --host="$SOURCE_HOST" --port=$SOURCE_PORT --username="$SOURCE_USER" --no-password)

	log_source "Starting pg_dumpall now."

	pg_dumpall --host="$SOURCE_HOST" --port=$SOURCE_PORT --username="$SOURCE_USER" --no-password 2>$TEMP_FILE | gzip > "$PENDING_TARGET/all_databases_${DATE}.sql.gz"

	STATUS=${PIPESTATUS[0]}
	ERR=`< $TEMP_FILE`

	log_source "Returned from pg_dumpall. stderr:\n\n$ERR\n\nExit status: $STATUS\n"

	rm $PGPASSFILE

	if [ $STATUS -ne 0 ]; then

		SUCCESS=0
		SUBJECT="FAILURE: $SUBJECT"
		MESSAGE="Exit status: $STATUS.\n\nOutput collected from stderr is below. See $SOURCE_LOG_FILE on `hostname -s` for more information.\n\nNOTE: $PENDING_TARGET will not be cleaned up automatically.\n\n$ERR"

	else

		SUCCESS=1
		SUBJECT="Success: $SUBJECT"
		MESSAGE="No errors were reported.\n\nSee $SOURCE_LOG_FILE on `hostname -s` for more information."

	fi

	do_finalise

}

function do_finalise {

	if [ $SUCCESS -eq 1 ]; then

		RESULT="SUCCEEDED"
		NOTIFY="$NOTIFY_EMAIL"

	else

		RESULT="FAILED"
		NOTIFY="$ERROR_EMAIL"

	fi

	log_message "$SUBJECT"
	log_source "Backup operation: $RESULT"

	echo -e "$MESSAGE" | mail -s "$SUBJECT" "$NOTIFY"

	log_source "Result notification sent:\n\nTo: $NOTIFY\nSubject: $SUBJECT\nMessage:\n$MESSAGE.\n"

	if [ $SUCCESS -eq 1 ]; then

		mv "$PENDING_TARGET" "$TARGET_MOUNT_POINT/snapshots/$SOURCE_NAME"
		rm -f "$TARGET_MOUNT_POINT/latest/$SOURCE_NAME"
		ln -s "$TARGET_MOUNT_POINT/snapshots/$SOURCE_NAME/$DATE" "$TARGET_MOUNT_POINT/latest/$SOURCE_NAME"

		log_source "Snapshot moved from 'pending' to 'latest'.\n"

		if [ $SOURCE_TYPE = "rsync_shadow" ]; then

			log_source "Closing shadow copy."

			ssh -F "$SCRIPT_DIR/ssh_config" -p $SSH_PORT -i "$SSH_KEY" "$SSH_USER@$SOURCE_HOST" "//`hostname -s`/vss/close_copy.cmd $SHADOW_PATH $DATE" > $TEMP_FILE 2>&1

			STATUS=$?
			ERR=`< $TEMP_FILE`

			log_source "Returned from close_copy.cmd. Output:\n\n$ERR\n\nExit status: $STATUS\n"

			if [ $STATUS -ne 0 ]; then

				SUBJECT="WARNING: $SUBJECT"
				MESSAGE="Unable to close shadow copy. Exit status: $STATUS.\n\nOutput collected from stderr is below.\n\n$ERR"

				echo -e "$MESSAGE" | mail -s "$SUBJECT" "$ERROR_EMAIL"

				log_source "Error notification sent:\n\nTo: $ERROR_EMAIL\nSubject: $SUBJECT\nMessage:\n$MESSAGE.\n"

			fi

		fi

	fi

	rm $TEMP_FILE

}

for TARGET_FILE in `get_targets`; do

	TARGET_NAME=`basename "$TARGET_FILE"`
	TARGET_MOUNT_POINT=
	TARGET_MOUNT_CHECK=1

	. "$TARGET_FILE"

    check_target || continue

	log_message "Found target volume for $TARGET_NAME at $TARGET_MOUNT_POINT. Initiating backup sequence."

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

				log_error "Unable to find source file $SOURCE_FILE. Ignoring this source."
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

		SOURCE_LOG_FILE="$TARGET_MOUNT_POINT/logs/$SOURCE_NAME/$SOURCE_NAME-$DATE.log"
		TEMP_FILE=`mktemp`
		PENDING_TARGET="$TARGET_MOUNT_POINT/snapshots/.pending/$SOURCE_NAME/$DATE"

		log_source "Backup operation commencing. Environment:\n\n`printenv`\n"

		mkdir -p "$PENDING_TARGET"

		log_source "Target directory created.\n"

		case $SOURCE_TYPE in

			rsync)

				log_message "Attempting rsync backup of '$SOURCE_NAME' to '$TARGET_NAME'..."

				(do_rsync $SOURCE_USER@$SOURCE_HOST::"$SOURCE_PATH/" &)

				;;

			rsync_ssh)

				log_message "Attempting rsync backup of '$SOURCE_NAME' to '$TARGET_NAME' over SSH..."

				(do_rsync $SSH_USER@$SOURCE_HOST:"$SOURCE_PATH/" -e "ssh -F '$SCRIPT_DIR/ssh_config' -p $SSH_PORT -i '$SSH_KEY'" &)

				;;

			rsync_shadow)

				log_message "Attempting rsync backup of '$SOURCE_NAME' to '$TARGET_NAME' with shadow copy..."

				log_source "Creating shadow copy."

				ssh -F "$SCRIPT_DIR/ssh_config" -p $SSH_PORT -i "$SSH_KEY" "$SSH_USER@$SOURCE_HOST" "//`hostname -s`/vss/create_copy.cmd $SHADOW_PATH $DATE $SHADOW_VOLUMES" > $TEMP_FILE 2>&1

				STATUS=$?
				ERR=`< $TEMP_FILE`

				log_source "Returned from create_copy.cmd. Output:\n\n$ERR\n\nExit status: $STATUS\n"

				if [ $STATUS -ne 0 ]; then

					SUBJECT="FAILURE: $SUBJECT"
					MESSAGE="Unable to create shadow copy. Exit status: $STATUS.\n\nOutput collected from stderr is below.\n\n$ERR"
					do_finalise

				else

					# allow shadow copy to "settle"
					sleep 5

					(do_rsync $SOURCE_USER@$SOURCE_HOST::"$SOURCE_PATH/$DATE/" &)

				fi

				;;

			mysql)

				log_message "Attempting MySQL backup of '$SOURCE_NAME' to '$TARGET_NAME'..."

				(do_mysql &)

				;;

			postgres)

				log_message "Attempting PostgreSQL backup of '$SOURCE_NAME' to '$TARGET_NAME'..."

				(do_postgres &)

				;;

			*)

				log_error "Invalid source type for '$SOURCE_NAME'. Ignoring this source."

				;;

		esac

	done

done

