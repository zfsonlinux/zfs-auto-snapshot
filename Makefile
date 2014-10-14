PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)/etc/cron.d
	install -d $(DESTDIR)/etc/cron.daily
	install -d $(DESTDIR)/etc/cron.hourly
	install -d $(DESTDIR)/etc/cron.weekly
	install -d $(DESTDIR)/etc/cron.monthly
	install -m 0644 etc/zfs-auto-snapshot.cron.frequent $(DESTDIR)/etc/cron.d/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.hourly   $(DESTDIR)/etc/cron.hourly/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.daily    $(DESTDIR)/etc/cron.daily/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.weekly   $(DESTDIR)/etc/cron.weekly/zfs-auto-snapshot
	install etc/zfs-auto-snapshot.cron.monthly  $(DESTDIR)/etc/cron.monthly/zfs-auto-snapshot
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install src/zfs-auto-snapshot.8 $(DESTDIR)$(PREFIX)/share/man/man8/zfs-auto-snapshot.8
	install -d $(DESTDIR)$(PREFIX)/sbin
	install src/zfs-auto-snapshot.sh $(DESTDIR)$(PREFIX)/sbin/zfs-auto-snapshot
