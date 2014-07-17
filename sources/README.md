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

`SOURCE_PATH` may be an array of source paths.

**Note:** By default, lime-machine copies symlinks as symlinks. You should consider adding `--copy-links`, `--copy-unsafe-links` or `--safe-links` to `RSYNC_OPTIONS` if necessary.

### Example "rsync_ssh" source configuration

    SOURCE_TYPE=rsync_ssh
    SOURCE_HOST=offsiteserver.com
    SOURCE_PATH=/home/offsiteserver
    SOURCE_EXCLUDE=$BACKUP_ROOT/sources/offsiteserver.exclude
    SSH_USER=offsiteserver
    SSH_PORT=2222
    SSH_KEY=$BACKUP_ROOT/secrets/ssh_private_key
    RSYNC_OPTIONS=()

See above for important notes regarding symlinks.

### Example "rsync_ssh_relay" source configuration

    SOURCE_TYPE=rsync_ssh_relay
    SOURCE_HOST=offsiteserver.com
    SOURCE_PATH=/home/offsiteserver
    SOURCE_USER=rsync_user
    SOURCE_SECRET=$BACKUP_ROOT/secrets/rsync_password
    SOURCE_EXCLUDE=$BACKUP_ROOT/sources/offsiteserver.exclude
    SSH_RELAY=relayserver.com
    SSH_USER=offsiteserver
    SSH_PORT=2222
    SSH_KEY=$BACKUP_ROOT/secrets/ssh_private_key
    LOCAL_PORT=
    RSYNC_OPTIONS=()

`LOCAL_PORT` is opened on the loopback interface of the relay and tunnelled over SSH to `SOURCE_HOST:873` (where `SOURCE_HOST` may be `localhost` or any other relay-accessible host). `LOCAL_PORT` MUST be unique to each active source on the backup server.

See above for important notes regarding symlinks.

### Example "rsync_shadow" source configuration

    SOURCE_TYPE=rsync_shadow
    SOURCE_HOST=server.domain.local
    SOURCE_PATH=backup
    SOURCE_USER=rsync_user
    SOURCE_SECRET=$BACKUP_ROOT/secrets/rsync_password
    SOURCE_EXCLUDE=$BACKUP_ROOT/sources/server.exclude
    SOURCE_SUB_PATH=/D
    SSH_USER=ssh_user
    SSH_PORT=2222
    SSH_KEY=$BACKUP_ROOT/secrets/ssh_private_key
    # This needs to be double-escaped!
    SHADOW_PATH=C:\\\\.backup
    SHADOW_VOLUMES="C D"
    RSYNC_OPTIONS=()

Shadow copies are mounted under `SHADOW_PATH` on the source server, which the rsync server must offer at `SOURCE_PATH` (which must not be an array). Commands to create and delete shadow copies are issued over SSH (simpler Linux-friendly alternatives aren't secure enough).

`SOURCE_SUB_PATH` is optional. It allows replication of particular volumes and/or folders from your shadow copy set, and may be an array.

See above for important notes regarding symlinks.

### Example "mysql" source configuration

    SOURCE_TYPE=mysql
    SOURCE_HOST=dbserver.domain.local
    SOURCE_USER=mysql_user
    SOURCE_PASSWORD=MYSQL_USER_PASSWORD
    MYSQLDUMP_OPTIONS=(--lock-all-tables --flush-logs)

### Example "mysql_ssh" source configuration

    SOURCE_TYPE=mysql_ssh
    SOURCE_HOST=dbserver.domain.local
    SOURCE_USER=mysql_user
    SOURCE_PASSWORD=MYSQL_USER_PASSWORD
    SSH_USER=ssh_user
    SSH_PORT=2222
    SSH_KEY=$BACKUP_ROOT/secrets/ssh_private_key
    LOCAL_PORT=
    MYSQLDUMP_OPTIONS=(--lock-all-tables --flush-logs)

`LOCAL_PORT` is opened on the loopback interface of the backup server and tunnelled over SSH to `localhost:3306` on the source server. It MUST be unique to each active source on the backup server.

### Example "postgres" source configuration

    SOURCE_TYPE=postgres
    SOURCE_HOST=dbserver.domain.local
    SOURCE_PORT=5432
    SOURCE_USER=postgres_user
    SOURCE_PASSWORD=POSTGRES_USER_PASSWORD

