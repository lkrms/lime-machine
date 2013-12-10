# sources

Data sources are defined here, one source per file. Settings may be provided in additional files, as long as they follow the convention `SOURCE_NAME.SETTINGS_TYPE`, e.g. `my_server.exclude` for rsync exclusions applied only to the `my_server` source.

Available source types:

* `rsync`: rsync without SSH tunneling, shadow copies or any other fancy features. Linux servers on the same network as the backup server will typically be configured this way.
* `rsync_ssh`: rsync over SSH. Recommended for backing up data hosted in the cloud.
* `rsync_shadow`: rsync with automatic Windows shadow copy creation and deletion. Requires a properly configured Windows server (i.e. with cygwin, SSH and rsync).
* `mysql`: MySQL server that accepts direct connections from the backup server.
* `postgres`: PostgreSQL server that accepts direct connections from the backup server.

Additional source types will be offered in future versions.

### Example "rsync" source configuration

    SOURCE_TYPE=rsync
    SOURCE_HOST=server.domain.local
    SOURCE_PATH=backup
    SOURCE_USER=rsync_user
    SOURCE_SECRET=$BACKUP_ROOT/secrets/rsync_password
    SOURCE_EXCLUDE=$BACKUP_ROOT/sources/server.exclude
    RSYNC_OPTIONS=(--whole-file)

lime-machine will cope if `RSYNC_OPTIONS` is a string rather than a array, but for best results, please provide an array. Empty array syntax is simply `()`.

### Example "rsync_ssh" source configuration

    SOURCE_TYPE=rsync_ssh
    SOURCE_HOST=offsiteserver.com
    SOURCE_PATH=/home/offsiteserver
    SOURCE_EXCLUDE=$BACKUP_ROOT/sources/offsiteserver.exclude
    SSH_USER=offsiteserver
    SSH_PORT=2222
    SSH_KEY=$BACKUP_ROOT/secrets/ssh_private_key
    RSYNC_OPTIONS=()

### Example "rsync_shadow" source configuration

    SOURCE_TYPE=rsync_shadow
    SOURCE_HOST=server.domain.local
    SOURCE_PATH=backup
    SOURCE_USER=rsync_user
    SOURCE_SECRET=$BACKUP_ROOT/secrets/rsync_password
    SOURCE_EXCLUDE=$BACKUP_ROOT/sources/server.exclude
    SSH_USER=ssh_user
    SSH_PORT=2222
    SSH_KEY=$BACKUP_ROOT/secrets/ssh_private_key
    # This needs to be double-escaped!
    SHADOW_PATH=C:\\\\.backup
    SHADOW_VOLUMES="C D"
    RSYNC_OPTIONS=()

Shadow copies are mounted under `SHADOW_PATH` on the source server, which the rsync server must offer at `SOURCE_PATH`. Commands to create and delete shadow copies are issued over SSH (simpler Linux-friendly alternatives aren't secure enough).

### Example "mysql" source configuration

    SOURCE_TYPE=mysql
    SOURCE_HOST=dbserver.domain.local
    SOURCE_USER=mysql_user
    SOURCE_PASSWORD=MYSQL_USER_PASSWORD
    MYSQLDUMP_OPTIONS=(--lock-all-tables --flush-logs)

### Example "postgres" source configuration

    SOURCE_TYPE=postgres
    SOURCE_HOST=dbserver.domain.local
    SOURCE_PORT=5432
    SOURCE_USER=postgres_user
    SOURCE_PASSWORD=POSTGRES_USER_PASSWORD

