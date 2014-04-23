# targets

Targets are defined here, one target per file. Each target represents a local mount point for a [large!] storage device, formatted using a robust filesystem like ext3 or ext4 and configured for mounting via `/etc/fstab`.

Syntax is very simple:

    TARGET_MOUNT_POINT=/mnt/backup_vol1
    TARGET_MOUNT_CHECK=1
    TARGET_ATTEMPT_MOUNT=0
    TARGET_UNMOUNT=0

If `TARGET_MOUNT_CHECK` is `0`, lime-machine won't check that `TARGET_MOUNT_POINT` is an active device mount point. **This should only be used if backing up data to a filesystem that is also used for other purposes.**

If `TARGET_ATTEMPT_MOUNT` is `1` (and `TARGET_MOUNT_CHECK` is also `1`), lime-machine will attempt to mount the target if it isn't already mounted.

If, in addition to the above, `TARGET_UNMOUNT` is also `1`, lime-machine will unmount the target after completing each backup / thinning operation.

