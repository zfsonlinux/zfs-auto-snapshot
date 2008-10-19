
NAME 

ZFS Automatic Snapshot SMF Service, version 0.11.2


DESCRIPTION 

This is a simple SMF service which can will take automatic,
scheduled snapshots of given ZFS filesystems and can perform simple
incremental or full backups of those filesystems.

Documentation for the service is contained in the manifest file,
zfs-auto-snapshot.xml.

Version 0.11 removes the simple GUI applications that were used to
create manifests, or select which filesystems should be included
in the canned instances. These are superceded by the time-slider-setup
application.

INSTALLATION

To install, as root, pkgadd SUNWzfs-auto-snapshot. This package now contains
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

			The "snap-children" property is ignored when using this
			fs-name value. Instead, the system automatically determines
			when it's able to take recursive, vs. non-recursive snapshots
			of the system, based on the values of the ZFS user properties.

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
			This value is ignored when setting zfs/fs-name='//'

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

 zfs/avoidscrub		Set to false by default, this determines whether
			we should avoid taking snapshots on any pools that have
			a scrub or resilver in progress.
			More info in the bugid:
			6343667 need itinerary so interrupted scrub/resilver
				doesn't have to start over


An example instance manifest is included in this archive.

SECURITY

The service is run by a restricted role "zfssnap", which is created when installing
the service if it doesn't already exist.  It has the "ZFS File System Administration"
RBAC Profile, as well as the solaris.smf.manage.zfs-auto-snapshot Authorization.
In order to see what the service is doing, you can view the SMF log files in
/var/svc/log for each service instance and syslog, with more detailed logging output
being sent to syslog when the "zfs/verbose" option is enabled.


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

