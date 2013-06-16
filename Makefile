all:

install:
	install -d $(DESTDIR)$(PREFIX)/etc/cron.d
	install -d $(DESTDIR)$(PREFIX)/etc/cron.daily
	install -d $(DESTDIR)$(PREFIX)/etc/cron.hourly
	install -d $(DESTDIR)$(PREFIX)/etc/cron.weekly
	install -d $(DESTDIR)$(PREFIX)/etc/cron.monthly
	install etc/zfs-auto-snapshot.cron.frequent $(DESTDIR)$(PREFIX)/etc/cron.d/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.hourly   $(DESTDIR)$(PREFIX)/etc/cron.hourly/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.daily    $(DESTDIR)$(PREFIX)/etc/cron.daily/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.weekly   $(DESTDIR)$(PREFIX)/etc/cron.weekly/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.monthly  $(DESTDIR)$(PREFIX)/etc/cron.monthly/zfs-auto-snapshot
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install src/zfs-auto-snapshot.8 $(DESTDIR)$(PREFIX)/share/man/man8/zfs-auto-snapshot.8
	install -d $(DESTDIR)$(PREFIX)/sbin
	install src/zfs-auto-snapshot.sh $(DESTDIR)$(PREFIX)/sbin/zfs-auto-snapshot
