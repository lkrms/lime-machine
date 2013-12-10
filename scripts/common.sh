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

