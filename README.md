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

1. install the scripts:

    ```
    wget https://github.com/gaerfield/zfs-auto-snapshot/archive/master.zip
    unzip master.zip
    cd zfs-auto-snapshot-master
    make systemd
    ```

2. optionally edit `zfs-auto-snapshot-frequent.timer` to snapshot more often and `zfs-auto-snapshot-frequent.service` to keep more snapshots by (dont forget to `systemctl daemon-reload`):

    ```
    cp /lib/systemd/system/zfs-auto-snapshot-frequent.timer /usr/systemd/system/
    cp /lib/systemd/system/zfs-auto-snapshot-frequent.service /usr/systemd/system/

    # in zfs-auto-snapshot-frequent.timer change OnCalendar from '*:0/15' (every 15 minutes) to i.e. '*:0/5' (every 5 minutes)
    [Timer]
    OnCalendar=*:0/5

    # in zfs-auto-snapshot-frequent.service the number in --keep should match the count of collected snapshots per hour (60/5 = 12)
    [Service]
    ExecStart=/usr/bin/zfs-auto-snapshot --quiet --syslog --label=frequent --keep=12 //
    ```

3. enable zfs snapshots: `zfs set com.sun:auto-snapshot=true pool/dataset`

4. start timers:

    ```
    systemctl start zfs-auto-snapshot-monthly.timer
    systemctl start zfs-auto-snapshot-weekly.timer
    systemctl start zfs-auto-snapshot-daily.timer
    systemctl start zfs-auto-snapshot-hourly.timer
    systemctl start zfs-auto-snapshot-frequent.timer
    ```

[bkoop]: https://briankoopman.com/zfs-automated-snapshots/
[dtim]: https://wiki.archlinux.org/index.php/Systemd/Timers
