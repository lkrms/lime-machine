# config

Settings relevant to all sources and targets are defined here.

Copy the `*-default` files without the `-default` suffix to get started, e.g.

    $ cp settings-default settings
    $ cp exclude.always-default exclude.always

### settings (REQUIRED)

Important lime-machine settings like `NOTIFY_EMAIL` are defined in this file.

### exclude.always (REQUIRED)

Every call to rsync includes an `--exclude-from /path/to/exclude.always` option.

**Please check the contents of this file, to ensure that no important data is excluded from your backups.**

