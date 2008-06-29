#!/bin/ksh

#
# Copyright 2006 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

#
# This script implements a simple wizard to schedule the taking of regular
# snapshots of this file system. Most of the interesting stuff is at the bottom.
#

MAIN_TITLE="Take regular ZFS snapshots"


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

function show_summary {
  # let's give the user a summary of what we've done:
  echo "SMF instance built to take snapshots using variables:"
  echo "interval=$INTERVAL"
  echo "period=$PERIOD"
  echo "keep_num=$KEEP_SNAP"
  echo "recurse=$SNAP_CHILDREN"

  TITLE="${MAIN_TITLE}: Summary"
  TEXT="The following snapshot schedule will be created :\n\n\
  Filesystem = ${FILESYS}\n\
  Interval = ${INTERVAL}\n\
  Period = ${PERIOD}\n\
  Keep snapshots = ${KEEP_SNAP}\n\
  Snapshot Children = ${SNAP_CHILDREN}\n\n\
  Do you want to write this auto-snapshot manifest now ?"
  zenity --question --title="${TITLE}" --text="${TEXT}"
  if [ $? -eq 1 ]
  then
    exit 1;
  fi

}


## Functions out of the way, we can start the wizard properly

if [ "$#" != 1 ]
then
  echo "Usage: zfs-auto-snapshot-admin.sh [zfs filesystem name]"
  exit 1;
fi

FILESYS=$1

#zfs list $FILESYS 2>&1 1> /dev/null
if [ $? -ne 0 ]
then
  echo "Unable to see filesystem $1. Exiting now."
  exit 1;
fi

get_interval
get_period
get_maxsnap
get_snap_children
show_summary

ESCAPED_NAME=$(echo $1 | sed -e 's#/#-#g')

# Now we can build an SMF manifest to perform these actions...

cat > auto-snapshot-instance.xml <<EOF
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type='manifest' name='$ESCAPED_NAME'>
<service
	name='system/filesystem/zfs/auto-snapshot'
	type='service'
	version='1'>
	<create_default_instance enabled='false' />

	<instance name='$ESCAPED_NAME' enabled='false' >

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
	</property_group>

	</instance>

	<stability value='Unstable' />
</service>
</service_bundle>
EOF

echo "Thanks, now import the SMF manifest, using the command :"
echo ""
echo "  # svccfg import auto-snapshot-instance.xml"
echo ""
echo "then issue the command :"
echo "  # svcadm enable svc:/system/filesystem/zfs/auto-snapshot:$ESCAPED_NAME"
echo ""
echo "You can see what work will be done by checking your crontab."
