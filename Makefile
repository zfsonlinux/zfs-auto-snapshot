PREFIX := /usr/local
SYSTEMD_HOME := /lib/systemd/system
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

systemd:
	install -d $(DESTDIR)/lib/systemd/system/
	install timers/zfs-auto-snapshot-frequent.service	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-frequent.service
	install timers/zfs-auto-snapshot-frequent.timer	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-frequent.timer
	install timers/zfs-auto-snapshot-hourly.service	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-hourly.service
	install timers/zfs-auto-snapshot-hourly.timer	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-hourly.timer
	install timers/zfs-auto-snapshot-daily.service	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-daily.service
	install timers/zfs-auto-snapshot-daily.timer	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-daily.timer
	install timers/zfs-auto-snapshot-weekly.service	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-weekly.service
	install timers/zfs-auto-snapshot-weekly.timer	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-weekly.timer
	install timers/zfs-auto-snapshot-monthly.service	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-monthly.service
	install timers/zfs-auto-snapshot-monthly.timer	$(DESTDIR)/$(SYSTEMD_HOME)/zfs-auto-snapshot-monthly.timer
	install -d $(DESTDIR)$(PREFIX)/share/man/man8
	install src/zfs-auto-snapshot.8 $(DESTDIR)$(PREFIX)/share/man/man8/zfs-auto-snapshot.8
	install -d $(DESTDIR)$(PREFIX)/sbin
	install src/zfs-auto-snapshot.sh $(DESTDIR)$(PREFIX)/sbin/zfs-auto-snapshot
	systemctl enable zfs-auto-snapshot-daily.timer
	systemctl enable zfs-auto-snapshot-frequent.timer
	systemctl enable zfs-auto-snapshot-hourly.timer
	systemctl enable zfs-auto-snapshot-daily.timer
	systemctl enable zfs-auto-snapshot-weekly.timer
	systemctl enable zfs-auto-snapshot-monthly.timer
