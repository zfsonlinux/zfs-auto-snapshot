#!/bin/sh

# zfs-auto-snapshot for Linux
# Automatically create, rotate, and destroy periodic ZFS snapshots.
# Copyright 2011 Darik Horn <dajhorn@vanadac.com>
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA
#

# Set the field separator to a literal tab and newline.
IFS="	
"

# Set default program options.
opt_backup_full=''
opt_backup_incremental=''
opt_default_exclude=''
opt_dry_run=''
opt_keep=''
opt_label=''
opt_prefix='zfs-auto-snap'
opt_recursive=''
opt_sep='_'
opt_setauto=''
opt_syslog=''
opt_skip_scrub=''
opt_verbose=''


print_usage ()
{
	echo "Usage: $0 [options] [-l label] <'//' | name [name...]>
  --default-exclude  Exclude objects if com.sun:auto-snapshot is unset.
  -d, --debug        Print debugging messages.
  -n, --dry-run      Print actions without actually doing anything.
  -s, --skip-scrub   Do not snapshot filesystems in scrubbing pools.
  -h, --help         Print this usage message.
  -k, --keep=NUM     Keep NUM recent snapshots and destroy older snapshots.
  -l, --label=LAB    LAB is usually 'hourly', 'daily', or 'monthly'.
  -p, --prefix=PRE   PRE is 'zfs-auto-snap' by default.
  -q, --quiet        Suppress warnings and notices at the console.
      --send-full=F  Send zfs full backup. Unimplemented.
      --send-incr=F  Send zfs incremental backup. Unimplemented.
      --sep=CHAR     Use CHAR to separate date stamps in snapshot names.
  -g, --syslog       Write messages into the system log.
  -r, --recursive    Snapshot named filesystem and all descendants.
  -v, --verbose      Print info messages.
      name           Filesystem and volume names, or '//' for all ZFS objects.
" 
}


print_log () # level, message, ...
{
	LEVEL=$1
	shift 1

	case $LEVEL in
		(eme*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.emerge $*
			echo Emergency: $* 1>&2
			;;
		(ale*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.alert $*
			echo Alert: $* 1>&2
			;;
		(cri*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.crit $*
			echo Critical: $* 1>&2
			;;
		(err*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.err $*
			echo Error: $* 1>&2
			;;
		(war*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.warning $*
			test -z "$opt_quiet" && echo Warning: $* 1>&2
			;;
		(not*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.notice $*
			test -z "$opt_quiet" && echo $*
			;;
		(inf*)
			# test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.info $*
			test -n "$opt_verbose" && echo $*
			;;
		(deb*)
			# test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.debug $*
			test -n "$opt_debug" && echo Debug: $*
			;;
		(*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" $*
			echo $* 1>&2
			;;
	esac
}


do_run ()
{
	if [ -n "$opt_dry_run" ]
	then
		echo $*
		RC="$?"
	else
		eval $*
		RC="$?"
		if [ "$RC" -eq 0 ]
		then
			print_log debug "$*"
		else
			print_log warning "$* returned $RC"
		fi
	fi
	return "$RC"
}

# main ()
# {

DATE=$(date +%F-%H%M)

GETOPT=$(getopt \
  --longoptions=default-exclude,dry-run,skip-scrub,recursive \
  --longoptions=keep:,label:,prefix:,sep: \
  --longoptions=debug,help,quiet,syslog,verbose \
  --options=dnshl:k:rs:qgv \
  -- "$@" ) \
  || exit 1

eval set -- "$GETOPT"

while [ "$#" -gt 0 ]
do
	case "$1" in
		(-d|--debug)
			opt_debug=1
			opt_quiet=''
			opt_verbose=1
			shift 1
			;;
		(--default-exclude)
			opt_default_exclude='1'
			shift 1
			;;
		(-n|--dry-run)
			opt_dry_run='1'
			shift 1
			;;
		(-s|--skip-scrub)
			opt_skip_scrub=1
			shift 1
			;;
		(-h|--help)
			print_usage
			exit 0
			;;
		(-k|--keep)
			if ! test "$2" -gt 0 2>/dev/null
			then
				print_log error "The $1 parameter must be a positive integer."
				exit 2
			fi
			opt_keep="$2"
			shift 2
			;;
		(-l|--label)
			opt_label="$2"
			shift 2
			;;
		(-p|--prefix)
			# @TODO: Parameter validation. See --sep below for the regex.
			opt_prefix="$2"
			;;
		(-q|--quiet)
			opt_debug=''
			opt_quiet='1'
			opt_verbose=''
			shift 1
			;;
		(-r|--recursive)
			opt_recursive=1
			shift 1
			;;
		(--sep)
			case "$2" in 
				([[:alnum:]_-.:\ ])
					:
					;;
				('')
					print_log error "The $1 parameter must be non-empty."
					exit 3
					;;
				(*)
					print_log error "The $1 parameter must be one alphanumeric character."
					exit 4
				;;
			esac
			opt_sep="$2"
			shift 2
			;;
		(-g|--syslog)
			opt_syslog=1
			shift 1
			;;
		(-v|--verbose)
			opt_quiet=''
			opt_verbose=1
			shift 1
			;;
		(--)
			shift 1
			break
			;;
	esac
done

if [ "$#" -eq 0 ]
then
	print_log error "The filesystem argument list is empty."
	exit 5
fi 

# Count the number of times '//' appears on the command line.
SLASHIES='0'
for ii in "$@"
do
	test "$ii" = '//' && SLASHIES=$(( $SLASHIES + 1 ))
done

if [ "$#" -gt 1 -a "$SLASHIES" -gt 0 ]
then
	print_log error "The // must be the only argument if it is given."
	exit 6
fi

# These are the only times that `zpool status` or `zfs list` are invoked, so
# this program for Linux has a much better runtime complexity than the similar
# Solaris implementation.

ZPOOL_STATUS=$(env LC_ALL=C zpool status 2>&1 ) \
  || { print_log error "zpool status $?: $ZPOOL_STATUS"; exit 7; }

ZFS_LIST=$(env LC_ALL=C zfs list -H -t filesystem,volume -s name \
  -o name,com.sun:auto-snapshot,com.sun:auto-snapshot:"$opt_label") \
  || { print_log error "zfs list $?: $ZFS_LIST"; exit 8; }

SNAPSHOTS_OLD=$(env LC_ALL=C zfs list -H -t snapshot -S creation -o name) \
  || { print_log error "zfs list $?: $SNAPSHOTS_OLD"; exit 9; }


# Verify that each argument is a filesystem or volume.
for ii in "$@"
do
	test "$ii" = '//' && continue 1
	while read NAME PROPERTIES
	do
		test "$ii" = "$NAME" && continue 2
	done <<-HERE
	$ZFS_LIST
	HERE
	print_log error "$ii is not a ZFS filesystem or volume."
	exit 10
done

# Get a list of pools that are being scrubbed.
ZPOOLS_SCRUBBING=$(echo "$ZFS_STATUS" | awk -F ': ' \
  '$1 ~ /^ *pool$/ { pool = $2 } ; \
   $1 ~ /^ *scan$/ && $2 ~ /scrub in progress/ { print pool }' \
  | sort ) 

# Get a list of pools that cannot do a snapshot.
ZPOOLS_NOTREADY=$(echo "$ZFS_STATUS" | awk -F ': ' \
  '$1 ~ /^ *pool$/ { pool = $2 } ; \
   $1 ~ /^ *state$/ && $2 !~ /ONLINE|DEGRADED/ { print pool } ' \
  | sort)

# Get a list of objects for which snapshots are explicitly disabled.
NOAUTO=$(echo "$ZFS_LIST" | awk -F '\t' \
  'tolower($2) ~ /false/ || tolower($3) ~ /false/ {print $1}')

# If the --default-exclude flag is set, then exclude all objects that lack
# an explicit com.sun:auto-snapshot* property. Otherwise, include them.
if [ -n "$opt_default_exclude" ]
then
	# Get a list of objects for which snapshots are explicitly enabled.
	CANDIDATES=$(echo "$ZFS_LIST" | awk -F '\t' \
	  'tolower($2) ~ /true/ || tolower($3) ~ /true/ {print $1}')
else
	# Invert the NOAUTO list.
	CANDIDATES=$(echo "$ZFS_LIST" | awk -F '\t' \
	  'tolower($2) !~ /false/ && tolower($3) !~ /false/ {print $1}')
fi

# Initialize the list of objects that will get a recursive snapshot.
TARGETS_RECURSIVE=''

# Initialize the list of objects that will get a non-recursive snapshot.
TARGETS_REGULAR=''

for ii in $CANDIDATES
do
	# Qualify object names so variable globbing works properly.
	# Suppose ii=tanker/foo and jj=tank sometime during the loop.
	# Just testing "$ii" != ${ii#$jj} would incorrectly match.
	iii="$ii/"

	# Exclude objects that are not named on the command line.
	IN_ARGS='0'
	for jj in "$@"
	do
		if [ "$jj" = '//' -o "$jj" = "$ii" ]
		then
			IN_ARGS=$(( $IN_ARGS + 1 ))
		fi
	done
	if [ "$IN_ARGS" -eq '0' ]
	then
		continue
	fi

	# Exclude objects in pools that cannot do a snapshot.
	for jj in $ZPOOLS_NOTREADY
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# Check whether the pool name is a prefix of the object name.
		if [ "$iii" != "${iii#$jjj}" ]
		then
			print_log info "Excluding $ii because pool $jj is not ready."
			continue 2
		fi
	done

	# Exclude objects in scrubbing pools if the --skip-scrub flag is set.
	test -z "$opt_skip_scrub" && for jj in $ZPOOLS_SCRUBBING
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# Check whether the pool name is a prefix of the object name.
		if [ "$iii" != "${iii#$jjj}" ]
		then
			print_log info "Excluding $ii because pool $jj is scrubbing."
			continue 2
		fi
	done

	for jj in $NOAUTO
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# The --recusive switch only matters for non-wild arguments.
		if [ -z "$opt_recursive" -a "$1" != '//' ]
		then
			# Snapshot this object non-recursively.
			print_log debug "Including $ii for regular snapshot."
			TARGETS_REGULAR="${TARGETS_REGULAR:+$TARGETS_REGULAR	}$ii" # nb: \t
			continue 2
		# Check whether the candidate name is a prefix of any excluded object name.
		elif [ "$jjj" != "${jjj#$iii}" ]
		then
			# Snapshot this object non-recursively.
			print_log debug "Including $ii for regular snapshot."
			TARGETS_REGULAR="${TARGETS_REGULAR:+$TARGETS_REGULAR	}$ii" # nb: \t
			continue 2
		fi
	done

	for jj in $TARGETS_RECURSIVE
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# Check whether any included object is a prefix of the candidate name.
		if [ "$iii" != "${iii#$jjj}" ]
		then
			print_log debug "Excluding $ii because $jj includes it recursively."
			continue 2
		fi
	done

	# Append this candidate to the recursive snapshot list because it:
	#
	#   * Does not have an exclusionary property.
	#   * Is in a pool that can currently do snapshots.
	#   * Does not have an excluded descendent filesystem.
	#   * Is not the descendant of an already included filesystem.
	#
	print_log debug "Including $ii for recursive snapshot."
	TARGETS_RECURSIVE="${TARGETS_RECURSIVE:+$TARGETS_RECURSIVE	}$ii" # nb: \t
done

# Summary statistics.
DESTRUCTION_COUNT='0'
SNAPSHOT_COUNT='0'
WARNING_COUNT='0'

# Linux lacks SMF and the notion of an FMRI event.
FMRI_EVENT='-'

# Create the snapshot using these arguments.
SNAPSHOT_PROPERTIES="-o com.sun:auto-snapshot-desc='$FMRI_EVENT'"
SNAPSHOT_NAME="$opt_prefix${opt_label:+$opt_sep$opt_label-$DATE}"

# The expression for old snapshots.                 -YYYY-MM-DD-HHMM
SNAPSHOT_MATCH="$opt_prefix${opt_label:+?$opt_label}????????????????"

test -n "$TARGETS_REGULAR" \
  && print_log info "Doing regular snapshots of $TARGETS_REGULAR"

test -n "$TARGETS_RECURSIVE" \
  && print_log info "Doing recursive snapshots of $TARGETS_RECURSIVE"

test -n "$opt_dry_run" \
  && print_log info "Doing a dry run. Not running these commands..."


for ii in $TARGETS_REGULAR
do
	if do_run "zfs snapshot $SNAPSHOT_PROPERTIES '$ii@$SNAPSHOT_NAME'"
	then
		SNAPSHOT_COUNT=$(( $SNAPSHOT_COUNT +1 ))
	else
		WARNING_COUNT=$(( $WARNING_COUNT +1 ))
		continue
	fi

	# Retain at most $opt_keep number of old snapshots of this filesystem,
	# including the one that was just recently created.
	if [ -z "$opt_keep" ]
	then
		continue
	fi
	KEEP="$opt_keep"

	for jj in $SNAPSHOTS_OLD
	do
		# Check whether this is an old snapshot of the filesystem.
		if [ -z "${jj#$ii@$SNAPSHOT_MATCH}" ]
		then
			KEEP=$(( $KEEP - 1 ))
			if [ "$KEEP" -le 0 ]
			then
				if do_run "zfs destroy '$jj'"
				then
					DESTRUCTION_COUNT=$(( $DESTRUCTION_COUNT +1 ))
				else
					WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
				fi
			fi
		fi
	done
done

for ii in $TARGETS_RECURSIVE
do
	if do_run "zfs snapshot $SNAPSHOT_PROPERTIES -r '$ii@$SNAPSHOT_NAME'" 
	then
		SNAPSHOT_COUNT=$(( $SNAPSHOT_COUNT +1 ))
	else
		WARNING_COUNT=$(( $WARNING_COUNT +1 ))
		continue
	fi 

	# Retain at most $opt_keep number of old snapshots of this filesystem,
	# including the one that was just recently created.
	if [ -z "$opt_keep" ]
	then
		continue
	fi
	KEEP="$opt_keep"

	# ASSERT: The old snapshot list is sorted by increasing age.
	for jj in $SNAPSHOTS_OLD
	do
		# Check whether this is an old snapshot of the filesystem.
		if [ -z "${jj#$ii@$SNAPSHOT_MATCH}" ]
		then
			KEEP=$(( $KEEP - 1 ))
			if [ "$KEEP" -le 0 ]
			then
				if do_run "zfs destroy -r '$jj'" 
				then
					DESTRUCTION_COUNT=$(( $DESTRUCTION_COUNT +1 ))
				else
					WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
				fi
			fi
		fi
	done
done

print_log notice "@$SNAPSHOT_NAME, \
$SNAPSHOT_COUNT created, $DESTRUCTION_COUNT destroyed, $WARNING_COUNT warnings."

exit 0
# }
