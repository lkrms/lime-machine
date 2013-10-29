# targets

Targets are defined here, one target per file. Each target represents a local mount point for a [large!] storage device, formatted using a robust filesystem like ext3 or ext4 and configured for automatic mounting via `/etc/fstab`.

Syntax is very simple:

    TARGET_MOUNT_POINT=/mnt/backup_vol1
    TARGET_MOUNT_CHECK=1

If `TARGET_MOUNT_CHECK` is `0`, lime-machine won't check that `TARGET_MOUNT_POINT` is an active device mount point. **This should only be used if backing up data to a filesystem that is also used for other purposes.**

