PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install src/zfs-auto-snapshot.8 $(DESTDIR)$(PREFIX)/share/man/man8/zfs-auto-snapshot.8
	install -d $(DESTDIR)$(PREFIX)/sbin
	install src/zfs-auto-snapshot.sh $(DESTDIR)$(PREFIX)/sbin/zfs-auto-snapshot
	install -d $(DESTDIR)$(PREFIX)/lib/systemd/system
	install timers/zfs-auto-daily.service $(DESTDIR)$(PREFIX)/lib/systemd/system/zfs-auto-daily.service
	install timers/zfs-auto-daily.timer $(DESTDIR)$(PREFIX)/lib/systemd/system/zfs-auto-daily.timer
	install timers/zfs-auto-hourly.service $(DESTDIR)$(PREFIX)/lib/systemd/system/zfs-auto-hourly.service
	install timers/zfs-auto-hourly.timer $(DESTDIR)$(PREFIX)/lib/systemd/system/zfs-auto-hourly.timer
	install timers/zfs-auto-weekly.service $(DESTDIR)$(PREFIX)/lib/systemd/system/zfs-auto-weekly.service
	install timers/zfs-auto-weekly.timer $(DESTDIR)$(PREFIX)/lib/systemd/system/zfs-auto-weekly.timer
