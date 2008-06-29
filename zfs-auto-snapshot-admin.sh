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
# Copyright 2006 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

#
# This script implements a simple wizard to schedule the taking of regular
# snapshots of this file system. Most of the interesting stuff is at the bottom.
#
# Since we'd like it to work with two different versions of zenity, we check
# the version string, and call the appropriate "_26" versions of functions
# if we need to. (zenity that ships in s10u2 is based on GNOME 2.6 and doesn't
# have the same functionality as the 2.14-based zenity)

MAIN_TITLE="Take regular ZFS snapshots"

function get_interval_26 {
  # Get an interval for taking snapshots
  # zenity 2.6 doesn't support the --text option to --list
  TITLE="${MAIN_TITLE}: Choose a time period for taking snapshots "
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

function show_summary {
  # let's give the user a summary of what we've done:

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
 show_summary

else
 # using a more up to date zenity
 get_interval
 get_period
 get_maxsnap
 get_snap_children
 show_summary
fi

# this is what works out the instance name: we can't have . or /
# characters in instance names, so we escape them appropriately
# eg. the auto snapshots for the ZFS filesystem tank/tims-fs are
# taken by the SMF instance
# svc:/system/filesystem/zfs/auto-snapshot:tank-tims--fs
ESCAPED_NAME=$(echo $1 | sed -e 's#-#--#g' | sed -e 's#/#-#g' \
		| sed -e 's#\.#-#g')

# Now we can build an SMF manifest to perform these actions...

cat > auto-snapshot-instance.xml <<EOF
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type='manifest' name='$ESCAPED_NAME'>
<service
	name='system/filesystem/zfs/auto-snapshot'
	type='service'
	version='0.4'>
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

echo "Thanks, now assuming the default SMF manifest has already been imported,"
echo "you can now import the manifest for this instance, using the command :"
echo ""
echo "  # svccfg import auto-snapshot-instance.xml"
echo ""
echo "then issue the command :"
echo "  # svcadm enable svc:/system/filesystem/zfs/auto-snapshot:$ESCAPED_NAME"
echo ""
echo "You can see what work will be done by checking your crontab."
