all:

install:
	install -d $(DESTDIR)$(PREFIX)/etc/cron.d
	install etc/zfs-auto-snapshot.cron $(DESTDIR)$(PREFIX)/etc/cron.d/zfs-auto-snapshot
	install -d $(DESTDIR)$(PREFIX)/sbin
	install src/zfs-auto-snapshot.sh $(DESTDIR)$(PREFIX)/sbin/zfs-auto-snapshot
