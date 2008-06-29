
NAME 

ZFS Automatic Snapshot SMF Service, version 0.7



DESCRIPTION 

This is a *prototype* of a simple SMF service which you can configure to 
take automatic, scheduled snapshots of any given ZFS filesystem as well
as perform simple incremental or full backups of that filesystem.

To use the service, the user must install the method script, import the default
instance, and then create instances for each ZFS filesystem that should be
managed by the service.

Documentation for the service instance is contained in the manifest file,
zfs-auto-snapshot.xml.

We also bundle a simple GUI application, which will query the user for the
properties required, and will proceed to build an instance manifest. This
GUI is documented as part of the installation instructions below.



INSTALLATION

To install, as root, run the following commands:

# cp zfs-auto-snapshot/lib/svc/method/zfs-auto-snapshot /lib/svc/method
# svccfg import zfs-auto-snapshot/zfs-auto-snapshot.xml

Once you have installed these, you need to create an instance of the service
for each set of ZFS snapshots you want to take. The properties we need are:

 zfs/fs-name		The name of the filesystem

 zfs/interval		[ hours | days | months ]	

 zfs/keep		How many snapshots to retain. "all" keeps all snapshots.

 zfs/period		How often you want to take snapshots
			 (eg. every 10 days)

 zfs/snapshot-children	"true" if you would like to recursively take snapshots
			 of all child filesystems of the specified fs-name.

 zfs/backup		[ full | incremental | none ] 

 zfs/backup-save-cmd	The command string used to save the backup stream.

 zfs/backup-lock	You shouldn't need to change this - but it should be
			set to "unlocked" by default. We use it to indicate when
			a backup is running.

 zfs/label		A label that can be used to differentiate this set of
			backups from others, not required.


An example instance manifest is included in this archive.

The script "zfs-auto-snapshot-admin.sh" is a simple shell wrapper which uses
zenity, a scriptable GUI framework in GNOME, to write a service manifest
based on user input. 


# ./zfs-auto-snapshot-admin.sh
Usage: zfs-auto-snapshot-admin.sh [zfs filesystem name]


EXAMPLES

The following shows  me running it for the ZFS filesystem 
"tank/root_filesystem".

timf@haiiro[593] ./zfs-auto-snapshot-admin.sh tank/root_filesystem
[ a set of dialogs appear, asking for input ]
Thanks, now assuming the default SMF manifest has already been imported,
you can now import the manifest for this instance, using the command :

  # svccfg import auto-snapshot-instance.xml

then issue the command :
  # svcadm enable svc:/system/filesystem/zfs/auto-snapshot:tank-root_filesystem

You can see what work will be done by checking your crontab. As of version
0.7, all logging from the service is done from the method script using
the print_log function, which uses logger(1) to send message to syslogd(1M)
at priority level "daemon.notice".


SEE ALSO


More background about this service, along with implementation comments can be
found in web log posts at:

http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_prototype_1
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_smf_service
http://blogs.sun.com/timf/entry/and_also_for_s10u2_zfs
http://blogs.sun.com/timf/entry/smf_philosophy_more_on_zfs
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_now_with
http://blogs.sun.com/timf/entry/zfs_automatic_snapshot_service_logging

The ZFS Automatic Snapshot SMF Service is released under the terms of the CDDL.
