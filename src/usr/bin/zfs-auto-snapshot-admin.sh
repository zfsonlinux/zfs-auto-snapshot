#!/bin/ksh

#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License, Version 1.0 only
# (the "License").  You may not use this file except in compliance
# with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
# Copyright 2008 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

#
# There are two modes to this script - "simple" mode, which takes no options
# and lets a user select which filesystems should have automatic snapshots taken
# using one of the built-in default schedules, or "advanced" mode, which takes
# a filesystem as an argument, and constructs an SMF manifest for the user, but
# nothing else. (it's up to the user to import the manifest and start the
# service) We don't currently let the user set the "zfs/avoidscrub" option - and
# set it to "true" by default.
#


#
# Since we'd like it to work with two different versions of zenity, we check
# the version string, and call the appropriate "_26" versions of functions
# if we need to. (zenity that ships in s10u2 is based on GNOME 2.6 and doesn't
# have the same functionality as the 2.14-based zenity)
#

MAIN_TITLE="Take regular ZFS snapshots"

function get_interval_26 {
  # Get an interval for taking snapshots
  # zenity 2.6 doesn't support the --text option to --list
  TITLE="${MAIN_TITLE}: Choose a time period for taking snapshots."
  INTERVAL=$(zenity --list --title="${TITLE}" \
  --radiolist --column="select" \
  --column="interval" x "minutes" x "hours" x "days" x "months")
  if [ $? -eq 1 ]
  then
      exit 1;
  fi
  case $INTERVAL in
   'minutes')
	MAX_VAL=60
	;;
   'hours')
	MAX_VAL=24
	;;
    'days')
	MAX_VAL=31
	;;
    'months')
	MAX_VAL=12
	;;
   esac

}


function get_interval {
  # get an interval to take snapshots at
  TITLE="${MAIN_TITLE}: Time period"
  TEXT="Choose a time period for taking snapshots"
  INTERVAL=$(zenity --list --title="${TITLE}" --text="${TEXT}" \
  --radiolist --column="select" \
  --column="interval" x "minutes" x "hours" x "days" x "months")
  if [ $? -eq 1 ]
  then
      exit 1;
  fi
  case $INTERVAL in
   'minutes')
	MAX_VAL=60
	;;
   'hours')
	MAX_VAL=24
	;;
   'days')
	MAX_VAL=31
	;;
   'months')
	MAX_VAL=12
	;;
   esac

}

function get_period_26 {
  # work out the period we want between snapshots
  # zenity 2.6 doesn't support the --scale option, use a text entry instead.
  TITLE="${MAIN_TITLE}: Interval"
  TEXT="Enter how often you want to take snapshots (eg. every 10 ${INTERVAL})"
  PERIOD=$(zenity --entry --title="${TITLE}" --text="${TEXT}" \
 	 --entry-text=10)
  if [ $? -eq 1 ]
  then
    exit 1;
  fi

}

function get_period {
  # work out the period we want between snapshots
  TITLE="${MAIN_TITLE}: Interval"
  TEXT="Choose how often you want to take snapshots (eg. every 10 ${INTERVAL})"
  PERIOD=$(zenity --scale --title="${TITLE}" --text="${TEXT}" \
  --min-value=1 --max-value=${MAX_VAL} --value=10)
  if [ $? -eq 1 ]
  then
    exit 1;
  fi
}


function get_maxsnap_26 {
  # choose a number of snapshots to save
  # zenity 2.6 doesn't support the --scale option, use a text entry instead
  TITLE="${MAIN_TITLE}: Number to save"
  TEXT="Choose a maximum number of snapshots to keep, Cancel disables the limit\n\
  \n\
   (Note: once you hit this number of snapshots, the oldest will be\n\
    automatically deleted to make room)"
  KEEP_SNAP=$(zenity --entry --title="${TITLE}" \
  --text="${TEXT}" --entry-text="all")

  if [ $? -eq 1 ]
  then
   KEEP_SNAP="all"
  fi
}


function get_maxsnap {
  # choose a number of snapshots to save
  TITLE="${MAIN_TITLE}: Number to save"
  TEXT="Choose a maximum number of snapshots to keep, Cancel disables the limit\n\
  \n\
   (Note: once you hit this number of snapshots, the oldest will be\n\
    automatically deleted to make room)"
  KEEP_SNAP=$(zenity --scale --title="${TITLE}" \
  --text="${TEXT}" --value=1 --min-value=0 --max-value=100)

  if [ $? -eq 1 ]
  then
   KEEP_SNAP="all"
  fi
}

function get_snap_children {
  # decide if we want to snapshot children of this filesystem
  TITLE="${MAIN_TITLE}: Snapshot recursively"
  TEXT="Do you want to automatically snapshot all children of this filesystem ?"

  SNAP_CHILDREN=true
  $(zenity --question --text="$TEXT")
  if [ $? -eq 1 ]
  then
    SNAP_CHILDREN=false
  fi
}


function get_backup {
  # decide if we want to do backup of this filesystem
  TITLE="${MAIN_TITLE}: Remote backups"
  TEXT="Choose a type of backup to perform for this filesystem:"

  BACKUP=$(zenity --list --title="${TITLE}" --text="${TEXT}" \
  --radiolist --column="select" \
  --column="type" x "full" x "incremental" x "none")

  if [ $? -eq 1 ]
  then
      exit 1;
  fi

  case $BACKUP in
   'incremental' | 'full')
	get_backup_command
	;;
   *)
        BACKUP="none"
	;;
  esac

}

function get_backup_command {
  # ask the user which backup command they want to use.
  TITLE="${MAIN_TITLE}: Backup command"
  TEXT="Enter a command you wish to run on the backup stream.\
 eg. eval cat > /net/hostname/backup.\$\$"

  BACKUP_COMMAND=$(zenity --entry --title="${TITLE}" --text="${TEXT}" \
 	--entry-text="ssh timf@hostname \
/usr/bin/pfexec /usr/sbin/zfs receive tank/backup")
  if [ $? -eq 1 ]
  then
    exit 1;
  fi

}


function get_label {
  # ask the user if they want to attach a label to this instance
  TITLE="${MAIN_TITLE}: Label"
  TEXT="Choose a label you may use to distinguish this snapshot schedule\
 from others (Alphanumeric chars only. Cancel to leave blank.)"

  LABEL=$(zenity --entry --title="${TITLE}" --text="${TEXT}" \
 	 --entry-text="")
  if [ $? -eq 1 ]
  then
    LABEL=""
  fi
}

function show_summary {
  # let's give the user a summary of what we've done:

  TITLE="${MAIN_TITLE}: Summary"
  TEXT="The following snapshot schedule will be created :\n\n\
  Filesystem = ${FILESYS}\n\
  Interval = ${INTERVAL}\n\
  Period = ${PERIOD}\n\
  Keep snapshots = ${KEEP_SNAP}\n\
  Snapshot Children = ${SNAP_CHILDREN}\n\
  Backup = ${BACKUP}\n\
  Backup command = ${BACKUP_COMMAND}\n\
  Label = ${LABEL}\n\
  \n\
  Do you want to write this auto-snapshot manifest now ?"

  zenity --question --title="${TITLE}" --text="${TEXT}"
  if [ $? -eq 1 ]
  then
    exit 1;
  fi

}


#
# This function implements the simple mode  - rather than the advanced
# mode (which builds a manifest for automatic snapshots based on user input)
# This version is much simpler, and lets a user simply select the filesystems 
# they wish to have snapshots taken of, using the default monthly, daily, 
# and frequent snapshot schedules which have been preconfigured.
#
function run_gui {

	# ask the user to choose between configuring monthly, daily, hourly
	# or frequent snapshots. This is not internationalised, sorry.

	TITLE="${MAIN_TITLE}"
	TEXT="Choose a snapshot schedule to configure: 
	(run program again to configure additional schedules)"
	LABEL=$(zenity --list --title="${TITLE}" --text="${TEXT}" \
		--radiolist --column="select" \
		--column="Snapshot type" x "frequent" x "hourly" x "daily" x \
			 "weekly" x "monthly")

	if [ $? -eq 1 ]
	then
		exit 1;
	fi


	FILESYSTEMS=/tmp/zfs-auto-snapshot-admin.$$
	# record the current snapshot property state from all filesystems
	# changing strings to either TRUE|FALSE, which conveniently are also
	# the arguments that "zenity --list" uses to mark boxes as checked or not
	# on entry.
	zfs list -H -o com.sun:auto-snapshot:$LABEL,name -t filesystem | \
		  sed -e 's/^true/TRUE/g' \
		      -e 's/^false/FALSE/g' -e 's/^-/FALSE/g' > $FILESYSTEMS


	# obtain input from the user - output is a space separated list of
	# filesystems that have the checkbox selected.
	ZENITY_SELECTIONS=$(
	zenity --list --checklist --column="Enabled" --column="Filesystem" \
	--title="$TITLE" \
	--text="Select the filesystems for $LABEL automatic snapshots" \
	--separator=' ' \
	$(cat $FILESYSTEMS)
	)

	if [ $? -ne 0 ]
	then
		exit 1
	fi	

	# append a space to properly delimit the last item in the list
	export ZENITY_SELECTIONS="${ZENITY_SELECTIONS} "

	# Walk all filesystems, checking whether the user has selected each one
	# from the zenity dialog, then check to see whether the auto-snapshot
	# zfs property was already set, changing it when necessary.
	for fs in $(cat $FILESYSTEMS | awk '{print $2}')
	do
		if echo "$ZENITY_SELECTIONS" | grep "$fs " > /dev/null
		then
			# check to see if it's currently set to false
			if cat $FILESYSTEMS | grep "^FALSE[	 ]*$fs$" > /dev/null
			then
				# echo setting $fs to on
				zfs set com.sun:auto-snapshot:$LABEL=true $fs
			fi
	
		else
			# check to see if it's currently set to true
			if cat $FILESYSTEMS | grep "^TRUE[	 ]*$fs$" > /dev/null
			then
				# echo setting $fs to off
				zfs set com.sun:auto-snapshot:$LABEL=false $fs
			fi
		fi
	done
	rm $FILESYSTEMS
}

## Functions out of the way, we can start the wizard properly

if [ "$#" != 1 ]
then
  echo "Usage: zfs-auto-snapshot-admin.sh [ simple ] | [zfs filesystem name]"
  exit 1;
fi

if [ $1 == "simple" ]
then
	# run ourselves as root
	if [ -z $GKSU ]
	then
		export GKSU=true
		gksu $0 simple
		exit $?
	fi

	run_gui
	exit 0;
fi


FILESYS=$1

zfs list $FILESYS 2>&1 1> /dev/null
if [ $? -ne 0 ]
then
  echo "Unable to see filesystem $1. Exiting now."
  exit 1;
fi


VERSION=$(zenity --version)
if [ "$VERSION" == "2.6.0" ]
then
 get_interval_26
 get_period_26
 get_maxsnap_26
 get_snap_children
 get_backup
 get_label
 show_summary

else
 # using a more up to date zenity
 get_interval
 get_period
 get_maxsnap
 get_snap_children
 get_backup
 get_label
 show_summary
fi

# this is what works out the instance name: we can't have . or /
# characters in instance names, so we escape them appropriately
# eg. the auto snapshots for the ZFS filesystem tank/tims-fs are
# taken by the SMF instance
# svc:/system/filesystem/zfs/auto-snapshot:tank-tims--fs
ESCAPED_NAME=$(echo $1 | sed -e 's#-#--#g' | sed -e 's#/#-#g' \
		| sed -e 's#\.#-#g')
if [ ! -z "${LABEL}" ]
then
  ESCAPED_NAME="${ESCAPED_NAME},${LABEL}"
fi
# Now we can build an SMF manifest to perform these actions...

cat > auto-snapshot-instance.xml <<EOF
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type='manifest' name='$ESCAPED_NAME'>
<service
	name='system/filesystem/zfs/auto-snapshot'
	type='service'
	version='0.10'>
	<create_default_instance enabled='false' />

	<instance name='${ESCAPED_NAME}' enabled='false' >

        <exec_method
		type='method'
		name='start'
		exec='/lib/svc/method/zfs-auto-snapshot start'
		timeout_seconds='10' />

	<exec_method
		type='method'
		name='stop'
		exec='/lib/svc/method/zfs-auto-snapshot stop'
		timeout_seconds='10' />

        <property_group name='startd' type='framework'>
        	<propval name='duration' type='astring' value='transient' />
        </property_group>

        <!-- properties for zfs automatic snapshots -->
	<property_group name="zfs" type="application">

	  <propval name="fs-name" type="astring" value="$FILESYS" 
		   override="true"/>
	  <propval name="interval" type="astring" value="$INTERVAL"
		   override="true"/>
	  <propval name="period" type="astring" value="$PERIOD"
		   override="true"/>
	  <propval name="offset" type="astring" value="0"
		   override="true"/>
	  <propval name="keep" type="astring" value="$KEEP_SNAP"
		   override="true"/>
	  <propval name="snapshot-children" type="boolean" value="$SNAP_CHILDREN"
		   override="true"/>

	  <propval name="backup" type="astring" value="$BACKUP"
		   override="true"/>
	  <propval name="backup-save-cmd" type="astring" value="$BACKUP_COMMAND"
		   override="true"/>
	  <propval name="backup-lock" type="astring" value="unlocked"
		   override="true"/>

	  <propval name="label" type="astring" value="${LABEL}"
		   override="true"/>

	  <propval name="verbose" type="boolean" value="false"
		   override="true"/>

	  <propval name="avoidscrub" type="boolean" value="true"
		   override="true"/>

	</property_group>

	</instance>

	<stability value='Unstable' />
</service>
</service_bundle>
EOF

echo "Thanks, now assuming the default SMF manifest has already been imported,"
echo "you can now import the manifest for this instance, using the command :"
echo ""
echo "  # svccfg import auto-snapshot-instance.xml"
echo ""
echo "then issue the command :"
echo "  # svcadm enable \
svc:/system/filesystem/zfs/auto-snapshot:$ESCAPED_NAME"
echo ""
echo "You can see what work will be done by checking your crontab."
