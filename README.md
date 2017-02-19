# zfs-auto-snapshot

An alternative implementation of the zfs-auto-snapshot service for Linux
that is compatible with zfs-linux and zfs-fuse.

Automatically create, rotate, and destroy periodic ZFS snapshots. This is
the utility that creates the:

* @zfs-auto-snap_frequent,
* @zfs-auto-snap_hourly,
* @zfs-auto-snap_daily,
* @zfs-auto-snap_weekly, and
* @zfs-auto-snap_monthly

snapshots if it is installed.

## Installation using cron

This program is a posixly correct bourne shell script.  It depends only on
the zfs utilities and cron, and can run in the dash shell (using the scripts in
`etc`).

```
wget https://github.com/zfsonlinux/zfs-auto-snapshot/archive/master.zip
unzip master.zip
cd zfs-auto-snapshot-master
make install
```

## Installation using systemd

As suggested by [Brian Koopman][bkoop] this target uses [systemd-timers][dtim]
instead of cron.

```
wget https://github.com/gaerfield/zfs-auto-snapshot/archive/master.zip
unzip master.zip
cd zfs-auto-snapshot-master
make systemd
```

[bkoop]: https://briankoopman.com/zfs-automated-snapshots/
[dtim]: https://wiki.archlinux.org/index.php/Systemd/Timers
