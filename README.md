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

Copy the `.timer` and corresponding `.service` file to `/etc/systemd/system/`, and then enable the timers as follows:
```
sudo systemctl daemon-reload
sudo systemctl enable zfs-auto-daily.timer
sudo systemctl enable zfs-auto-weekly.timer
```
