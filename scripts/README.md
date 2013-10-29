# scripts

### start-backup.sh

If called without arguments, commences backup operations for all sources in `active-sources` to all available targets. Otherwise, takes sources from the command line and starts backing them up to all available targets, e.g.

    $ start-backup.sh my_source1 my_source2

After creating any required shadow copies, this script starts each backup operation in its own process, so it returns quickly. Subprocesses provide user feedback via email and log files.

