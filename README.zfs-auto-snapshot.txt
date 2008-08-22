
NAME 

ZFS Automatic Snapshot SMF Service, version 0.11


DESCRIPTION 

This is a simple SMF service which can will take automatic,
scheduled snapshots of given ZFS filesystems and can perform simple
incremental or full backups of those filesystems.

Documentation for the service is contained in the manifest file,
zfs-auto-snapshot.xml.

As of version 0.9 there is a simple GUI that allows the user to configure
which filesystems are to be included in the default canned SMF instances.
This GUI is installed in the GNOME menu under:

	Administration -> Automatic Snapshots

We also bundle a simple GUI application, which will query the user for the
properties required, and will then build an instance manifest. This
GUI is documented as part of the installation instructions below.


INSTALLATION

To install, as root, pkgadd TIMFauto-snapshot. This package now contains
several canned SMF instances. These are:

online          1:17:43 svc:/system/filesystem/zfs/auto-snapshot:hourly
online          1:17:46 svc:/system/filesystem/zfs/auto-snapshot:monthly
online          1:17:46 svc:/system/filesystem/zfs/auto-snapshot:daily
online          1:17:48 svc:/system/filesystem/zfs/auto-snapshot:frequent
online          1:17:49 svc:/system/filesystem/zfs/auto-snapshot:weekly

These instances use the special "//" fs-name to determine which filesystems
should be included in each snapshot schedule. See the description for "fs-name"
below.

The included instances have the following properties:

frequent	snapshots every 15 mins, keeping 4 snapshots
hourly		snapshots every hour, keeping 24 snapshots
daily		snapshots every day, keeping 31 snapshots
weekly		snapshots every week, keeping 7 snapshots
monthly		snapshots every month, keeping 12 snapshots

The :default service instance does not need to be enabled.

Additional instances of the service can also be created, for example to group
related sets of filesystems under a single service instance.

The properties each instance needs are:

 zfs/fs-name		The name of the filesystem. If the special filesystem
			name "//" is used, then the system snapshots only
			filesystems with the zfs user property 
			"com.sun:auto-snapshot:<label>" set to true, so to take
			frequent snapshots of tank/timf, run the following zfs
			command:

			# zfs set com.sun:auto-snapshot:frequent=true tank/timf

			When the "snap-children" property is set to "true",
			only locally-set dataset properties are used to
			determine which filesystems to snapshot -
			property inheritance is not respected in this case,
			but yeilds better performance for large dataset trees.

			The special filesystem name "##" is the reverse of the
			above - it snapshots all filesystems, except ones that are
			explicitly marked with a "com.sun:auto-snapshot:<label>"
			set to "false".  Using this zfs/fs-name value implicitly
			turns off the "snap-children" flag.

 zfs/interval		[ hours | days | months | none]	
			When set to none, we don't take automatic snapshots, but
			leave an SMF instance available for users to manually
			fire the method script whenever they want - useful for
			snapshotting on system events.

 zfs/keep		How many snapshots to retain - eg. setting this to "4"
			would keep only the four most recent snapshots. When each
			new snapshot is taken, the oldest is destroyed. If a snapshot
			has been cloned, the service will drop to maintenance mode
			when attempting to destroy that snapshot.  Setting to "all"
			keeps all snapshots.

 zfs/period		How often you want to take snapshots, in intervals
			set according to "zfs/interval"
			 (eg. every 10 days)

 zfs/snapshot-children	"true" if you would like to recursively take snapshots
			 of all child filesystems of the specified fs-name.

 zfs/backup		[ full | incremental | none ] 

 zfs/backup-save-cmd	The command string used to save the backup stream.

 zfs/backup-lock	You shouldn't need to change this - but it should be
			set to "unlocked" by default. We use it to indicate when
			a backup is running.

 zfs/label		A label that can be used to differentiate this set of
			snapshots from others, not required. If multiple 
			schedules are running on the same machine, using distinct
			labels for each schedule is needed - otherwise one
			schedule could remove snapshots taken by another schedule
			according to it's snapshot-retention policy.
			(see "zfs/keep")
			

 zfs/verbose		Set to false by default, setting to true makes the
			service produce more output about what it's doing.

 zfs/avoidscrub		Set to true by default, this determines whether
			we should avoid taking snapshots on any pools that have
			a scrub or resilver in progress.
			More info in the bugid:
			6343667 need itinerary so interrupted scrub/resilver
				doesn't have to start over


An example instance manifest is included in this archive.

The script "zfs-auto-snapshot-admin.sh" is a simple shell wrapper which uses
zenity, a scriptable GUI framework in GNOME, to write a service manifest
based on user input. 


# ./zfs-auto-snapshot-admin.sh
Usage: zfs-auto-snapshot-admin.sh [zfs filesystem name]


EXAMPLES

The following shows us running it for the ZFS filesystem 
"tank/root_filesystem".

timf@haiiro[593] ./zfs-auto-snapshot-admin.sh tank/root_filesystem
[ a set of dialogs appear, asking for input ]
Thanks, now assuming the default SMF manifest has already been imported,
you can now import the manifest for this instance, using the command :

  # svccfg import auto-snapshot-instance.xml

then issue the command :
  # svcadm enable svc:/system/filesystem/zfs/auto-snapshot:tank-root_filesystem


The service is run by a restricted role "zfssnap", which is created when installing
the service. It has the "ZFS File System Administration" RBAC Profile, as well
as the solaris.smf.manage.zfs-auto-snapshot Authorization. In order to see what
the service is doing, you can view the SMF log files in /var/svc/log for each
service instance and syslog, with more detailed logging output being sent to
the log files in the zfssnap role's home directory. (/export/home/zfssnap, by default)


SEE ALSO


More background about this service, along with implementation comments can be
found in web log posts at:

http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_prototype_1
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_smf_service
http://blogs.sun.com/timf/entry/and_also_for_s10u2_zfs
http://blogs.sun.com/timf/entry/smf_philosophy_more_on_zfs
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_now_with
http://blogs.sun.com/timf/entry/zfs_automatic_snapshot_service_logging
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_0_8
http://blogs.sun.com/timf/entry/zfs_automatic_for_the_people
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_0_10
http://blogs.sun.com/timf/entry/zfs_automatic_snapshots_0_11

The ZFS Automatic Snapshot SMF Service is released under the terms of the CDDL.

