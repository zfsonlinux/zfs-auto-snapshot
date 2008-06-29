ZFS Automatic Snapshot SMF Service, version 0.5

Introduction
-----------

This is a *prototype* of a simple SMF service which you can configure to 
take automatic, scheduled snapshots of any given ZFS filesystem.


Usage Instructions
------------------

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


An example instance manifest is included in this archive, and the default
instance (which should be disabled) is also documented.

The script "zfs-auto-snapshot-admin.sh" is a simple shell wrapper which uses
zenity, a scriptable GUI framework in GNOME, to write a service manifest
based on user input. 

# ./zfs-auto-snapshot-admin.sh
Usage: zfs-auto-snapshot-admin.sh [zfs filesystem name]

The following shows  me running it for the ZFS filesystem 
"tank/root_filesystem".

timf@haiiro[593] ./zfs-auto-snapshot-admin.sh tank/root_filesystem
[ a set of dialogs appear, asking for input ]
Thanks, now assuming the default SMF manifest has already been imported,
you can now import the manifest for this instance, using the command :

  # svccfg import auto-snapshot-instance.xml

then issue the command :
  # svcadm enable svc:/system/filesystem/zfs/auto-snapshot:tank-root_filesystem

You can see what work will be done by checking your crontab.

The ZFS Automatic Snapshot SMF Service is released under the terms of the CDDL.

More background detail about this service can be found in blog posts at:

http://blogs.sun.com/roller/page/timf?entry=zfs_automatic_snapshots_prototype_1
http://blogs.sun.com/roller/page/timf?entry=zfs_automatic_snapshots_smf_service
http://blogs.sun.com/roller/page/timf?entry=and_also_for_s10u2_zfs

