# zfs-auto-snapshot

An alternative implementation of the zfs-auto-snapshot service for Linux
that is compatible with [ZFS on Linux](http://zfsonlinux.org/).

Automatically create, rotate, and destroy periodic ZFS snapshots. This is
the utility that creates the:

* @zfs-auto-snap_frequent,
* @zfs-auto-snap_hourly,
* @zfs-auto-snap_daily,
* @zfs-auto-snap_weekly, and
* @zfs-auto-snap_monthly

snapshots if it is installed.

This program is a posixly correct bourne shell script.  It depends only on
the zfs utilities and cron, and can run in the dash shell (using the scripts
in `etc`).

## Installation using cron

```sh
wget https://github.com/zfsonlinux/zfs-auto-snapshot/archive/master.zip
unzip master.zip
cd zfs-auto-snapshot-master
make install
```

## Installation using systemd

```sh
wget https://github.com/zfsonlinux/zfs-auto-snapshot/archive/systemd.zip
unzip systemd.zip
cd zfs-auto-snapshot-systemd
make install enable
```

### Scheduling

See [systemd timers](https://wiki.archlinux.org/index.php/Systemd/Timers).

You can find some example `.timer` files in the `timers/` directory of this
repo. They will be installed when you run `make install` from the `systemd`
git branch.

If you wish to edit the timers, you will find them in the
`/usr/local/lib/systemd/system/` directory. Save the edited timers to
`/etc/systemd/system/` directory to override the default timers.

### Managing Which Pools to Snapshot

By default, the script will snapshot all pools automatically, unless they
have the `com.sun:auto-snapshot` property set to `false`.

To check the status of this property for all of your pools and datasets, run
the following command:

```sh
sudo zfs get com.sun:auto-snapshot
```

If you see an output like the following, then snapshots are enabled on this
pool:

```
NAME     PROPERTY               VALUE                  SOURCE
archive  com.sun:auto-snapshot  -                      -
```

To disable snapshots on this pool, issue the following command:

```sh
sudo zfs set com.sun:auto-snapshot=false archive
```

We can check with `zfs get` again, and this time our output should look like the following. If we see this, we know that snapshots have been disabled on this pool:

```
NAME     PROPERTY               VALUE                  SOURCE
archive  com.sun:auto-snapshot  false                  local
```

To disable snapshots on a single dataset, the command is very similar:

```sh
sudo zfs set com.sun:auto-snapshot=false archive/dataset
```
