# zfs-auto-snapshot

An alternative implementation of the zfs-auto-snapshot service for Linux
that is compatible with [ZFS on Linux](http://zfsonlinux.org/).

My fork removes the automatic installation of cron entries that do things
the user may not desire. This fork only installs the script and leaves manual
crontab/systemd-timer configuration up to the user.

This program is a posixly correct bourne shell script.  It depends only on
the zfs utilities, and can run in the dash shell.


Installation:
-------------
```
git clone https://github.com/ajhaydock/zfs-auto-snapshot.git
cd zfs-auto-snapshot
sudo make install
```


Scheduling:
-------------
I recommend scheduling this using [systemd timers](https://wiki.archlinux.org/index.php/Systemd/Timers).

You can find some example `.timer` files in the examples directory of this repo.

Copy the `.timer` and corresponding `.service` file to `/etc/systemd/system/`:
```
cp -f -v *.timer *.service /etc/systemd/system/
```
Then enable the timers as follows:
```
sudo systemctl daemon-reload
sudo systemctl start zfs-auto-hourly.timer && sudo systemctl enable zfs-auto-hourly.timer
sudo systemctl start zfs-auto-daily.timer && sudo systemctl enable zfs-auto-daily.timer
sudo systemctl start zfs-auto-weekly.timer && sudo systemctl enable zfs-auto-weekly.timer
```


Managing Which Pools to Snapshot
-------------
By default, the script will snapshot all pools automatically, unless they have the `com.sun:auto-snapshot` property set to `false`.

To check whether a pool has this property set, run the following command (where `archive` is the pool name):
```
sudo zfs get com.sun:auto-snapshot archive
```

If you see an output like the following, then snapshots are enabled on this pool:
```
NAME     PROPERTY               VALUE                  SOURCE
archive  com.sun:auto-snapshot  -                      -
```

To disable snapshots on this pool, issue the following command:
```
sudo zfs set com.sun:auto-snapshot=false archive
```

We can check with `zfs get` again, and this time our output should look like the following. If we see this, we know that snapshots have been disabled on this pool:
```
NAME     PROPERTY               VALUE                  SOURCE
archive  com.sun:auto-snapshot  false                  local
```
