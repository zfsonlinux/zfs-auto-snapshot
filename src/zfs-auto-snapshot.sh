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
opt_event='-'
opt_fast_zfs_list=''
opt_keep=''
opt_label=''
opt_prefix='zfs-auto-snap'
opt_recursive=''
opt_send_type=''
opt_send_host=''
opt_recv_pool=''
opt_send_opts=''
opt_send_only=''
opt_recv_opts=''
opt_send_ssh_opts=''
opt_send_mbuf_opts=''
opt_send_fallback=''
opt_sep='_'
opt_setauto=''
opt_syslog=''
opt_skip_scrub=''
opt_verbose=''
opt_pre_snapshot=''
opt_post_snapshot=''
opt_pre_send=''
opt_post_send=''
opt_do_snapshots=1

# Global summary statistics.
DESTRUCTION_COUNT='0'
SNAPSHOT_COUNT='0'
WARNING_COUNT='0'

# Other global variables.
SNAPSHOTS_OLD=''
SNAPS_DONE=''


print_usage ()
{
	echo "Usage: $0 [options] [-l label] <'//' | name [name...]>
  --default-exclude     Exclude datasets if com.sun:auto-snapshot is unset.
  -d, --debug           Print debugging messages.
  -e, --event=EVENT     Set the com.sun:auto-snapshot-desc property to EVENT.
      --fast            Use a faster zfs list invocation.
  -n, --dry-run         Print actions without actually doing anything.
  -s, --skip-scrub      Do not snapshot filesystems in scrubbing pools.
  -h, --help            Print this usage message.
  -k, --keep=NUM        Keep NUM recent snapshots and destroy older snapshots.
  -l, --label=LAB       LAB is usually 'hourly', 'daily', or 'monthly'.
  -p, --prefix=PRE      PRE is 'zfs-auto-snap' by default.
  -q, --quiet           Suppress warnings and notices at the console.
      --send-full=F     Send zfs full backup.
      --send-incr=F     Send zfs incremental backup.
      --send-fallback   Fallback from incremental to full if needed.
      --send-opts=F     Option(s) passed to 'zfs send'.
      --recv-opts=F     Option(s) passed to 'zfs receive'.
      --send-ssh-opts   Option(s) passed to 'ssh'.
      --send-mbuf-opts  Use mbuffer (with these options) between 'zfs send'
                        and 'ssh <host> zfs receive'.
      --send-only       Only send the the most recent snapshot
      --sep=CHAR        Use CHAR to separate date stamps in snapshot names.
  -g, --syslog          Write messages into the system log.
  -r, --recursive       Snapshot named filesystem and all descendants.
  -v, --verbose         Print info messages.
      --destroy-only    Only destroy older snapshots, do not create new ones.
      name              Filesystem and volume names, or '//' for all ZFS datasets.
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


do_run () # [argv]
{
	if [ -n "$opt_dry_run" ]
	then
		echo $*
		RC="$?"
	else
		eval $*
		RC="$?"
		if [ "$RC" -eq '0' ]
		then
			print_log debug "$*"
		else
			print_log warning "$* returned $RC"
		fi
	fi
	return "$RC"
}


find_last_snap () # dset, GLOB
{
	local snap="$1"
	local GLOB="$2"

	local dset="${snap%@*}"
	local last_snap
	local jj

	# STEP 1: Go through ALL snapshots that exist, look for exact
	#         match on dataset/volume (with snapshot matching 'GLOB').
	for jj in $SNAPSHOTS_OLD
	do
		# Check whether this is an old snapshot of the filesystem.
		if [ -z "${jj#$dset@$GLOB}" ]; then
			# We want the FIRST one (which is the last in time
			# before the one we just created in do_snapshot()).
			# Also, here we just need the snapshot name.
			last_snap="${jj#*@}"
			break
		fi
	done

	# NOTE: If we don't have any previous snapshots (for example, we've
	#       just created the first one) we can end up with last_snap=''
	#       here.
	#       If we're called with '--send-incr' we have to options:
	#         1: We change from incremental to full.
	#         2: We accept that the user have said INCR, and stick with
	#            it.
	#       Normally we do point 2, but if --send-fallback is specified,
	#       we allow it and convert to a full send instead.
	if [ "$opt_send_type" = "incr" -a -z "$last_snap" -a -z "$opt_send_fallback" ]; then
		if [ -n "$opt_verbose" ]; then
			echo > /dev/stderr "WARNING: No previous snapshots exist but we where called"
			echo > /dev/stderr "         with --send-incr. Can not continue."
			echo > /dev/stderr "         Please rerun with --send-full."
			echo > /dev/stderr "         Or use --send-fallback."
		fi
		return 1
	fi

	if [ -n "$opt_recursive" ]; then
		# STEP 2: Again, go through ALL snapshots that exists, but this
		#         time only look for the snapshots that 'starts with'
		#         the dataset/volume in question AND 'ends with'
		#         the exact snapshot name/date in step 2.
		for jj in $SNAPSHOTS_OLD
		do
			# When trying to find snapshots recurively, we MUST have a 'last_snap'
			# value. Othervise, it will match ALL snapshots for dset (if we had
			# used '"^$dset.*@$GLOB" only).
			if [ -z "$last_snap" ] && echo "$jj" | grep -qE "^$dset.*@$GLOB"; then
				# Use this as last snapshot name
				last_snap="${jj#*@}"
			fi

			if echo "$jj" | grep -qE "^$dset.*@$last_snap"; then
				echo $jj
			fi
		done
	else
		echo "$snap"
	fi

	return 0
}


do_snapshots () # properties, flags, snapname, oldglob, [targets...]
{
	local PROPS="$1"
	local FLAGS="$2"
	local NAME="$3"
	local GLOB="$4"
	local TARGETS="$5"
	local KEEP=''
	local RUNSNAP=1

	# global DESTRUCTION_COUNT
	# global SNAPSHOT_COUNT
	# global WARNING_COUNT
	# global SNAPSHOTS_OLD

	for ii in $TARGETS
	do
		if [ -n "$opt_do_snapshots" ]
		then
			if [ "$opt_pre_snapshot" != "" ]
			then
				do_run "$opt_pre_snapshot $ii $NAME" || RUNSNAP=0
			fi
			if [ $RUNSNAP -eq 1 ] && do_run "zfs snapshot $PROPS $FLAGS '$ii@$NAME'"
			then
				[ "$opt_post_snapshot" != "" ] && do_run "$opt_post_snapshot $ii $NAME"
				[ -n "$opt_send_host" ] && SNAPS_DONE="$SNAPS_DONE
$ii@$NAME"
				SNAPSHOT_COUNT=$(( $SNAPSHOT_COUNT + 1 ))
			else
				WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
				continue
			fi 
		fi

		[ -n "$opt_send_only" ] && tmp=$(find_last_snap "$ii@$NAME" "$GLOB")
		[ -n "$tmp" ] && SNAPS_DONE="$SNAPS_DONE
$tmp"

		# Retain at most $opt_keep number of old snapshots of this filesystem,
		# including the one that was just recently created.
		test -z "$opt_keep" && continue
		KEEP="$opt_keep"

		if [ -z "$opt_send_only" ]; then
			# ASSERT: The old snapshot list is sorted by increasing age.
			for jj in $SNAPSHOTS_OLD
			do
				# Check whether this is an old snapshot of the filesystem.
				if [ -z "${jj#$ii@$GLOB}" ]
				then
					KEEP=$(( $KEEP - 1 ))
					if [ "$KEEP" -le '0' ]
					then
						if do_run "zfs destroy $FLAGS '$jj'" 
						then
							DESTRUCTION_COUNT=$(( $DESTRUCTION_COUNT + 1 ))
						else
							WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
						fi
					fi
				fi
			done
		fi
	done
}

do_send () # snapname, oldglob
{
	local NAME="$1"
	local GLOB="$2"
	local RUNSEND=1
	local remote
	local ii
	local jj

	[ -n "$opt_send_mbuf_opts" ] && remote="mbuffer $opt_send_mbuf_opts |"
	remote="$remote ssh $opt_send_ssh_opts $opt_send_host"
	remote="$remote zfs receive $opt_recv_opts"

	# STEP 1: Go throug all snapshots we've created
	for ii in $SNAPS_DONE
	do
		opts=''
		SNAPS_SEND=''

		# STEP 2: Find the last snapshot
		SNAPS_SEND=$(find_last_snap "$ii" "$GLOB")

		# STEP 3: Go through all snapshots that is to be transfered and send them.
		for jj in $SNAPS_SEND
		do
			if [ -n "$opt_pre_send" ]; then
				do_run "$opt_pre_send $jj" || RUNSEND=0
			fi

			if [ $RUNSEND -eq 1 ]; then
				if [ "$opt_send_type" = "incr" ]; then
					if [ "$jj" = "$ii" -a -n "$opt_send_fallback" ]; then
						do_run "zfs send $opt_send_opts -R $ii | $remote -F $opt_recv_pool" \
							|| RUNSEND=0
					else
						do_run "zfs send $opt_send_opts -i $jj $ii | $remote $opt_recv_pool" \
							|| RUNSEND=0
					fi
				else
					do_run "zfs send $opt_send_opts -R $jj | $remote $opt_recv_pool" || RUNSEND=0
				fi

				if [ $RUNSEND = 1 -a -n "$opt_post_send" ]; then
					do_run "$opt_post_send $jj" || RUNSEND=0
				fi
			fi
		done
	done
}

# main ()
# {

GETOPT=$(getopt \
  --longoptions=default-exclude,dry-run,fast,skip-scrub,recursive \
  --longoptions=event:,keep:,label:,prefix:,sep: \
  --longoptions=debug,help,quiet,syslog,verbose \
  --longoptions=pre-snapshot:,post-snapshot:,destroy-only \
  --longoptions=send-full:,send-incr:,send-opts:,recv-opts: \
  --longoptions=send-ssh-opts:,send-mbuf-opts:,pre-send:,post-send: \
  --longoptions=send-fallback,send-only \
  --options=dnshe:l:k:p:rs:qgv \
  -- "$@" ) \
  || exit 128

eval set -- "$GETOPT"

while [ "$#" -gt '0' ]
do
	case "$1" in
		(-d|--debug)
			opt_debug='1'
			opt_quiet=''
			opt_verbose='1'
			shift 1
			;;
		(--default-exclude)
			opt_default_exclude='1'
			shift 1
			;;
		(-e|--event)
			if [ "${#2}" -gt '1024' ]
			then
				print_log error "The $1 parameter must be less than 1025 characters."
				exit 139
			elif [ "${#2}" -gt '0' ]
			then
				opt_event="$2"
			fi
			shift 2
			;;
		(--fast)
			opt_fast_zfs_list='1'
			shift 1
			;;
		(-n|--dry-run)
			opt_dry_run='1'
			shift 1
			;;
		(-s|--skip-scrub)
			opt_skip_scrub='1'
			shift 1
			;;
		(-h|--help)
			print_usage
			exit 0
			;;
		(-k|--keep)
			if ! test "$2" -gt '0' 2>/dev/null
			then
				print_log error "The $1 parameter must be a positive integer."
				exit 129
			fi
			opt_keep="$2"
			shift 2
			;;
		(-l|--label)
			opt_label="$2"
			shift 2
			;;
		(-p|--prefix)
			opt_prefix="$2"
			while test "${#opt_prefix}" -gt '0'
			do
				case $opt_prefix in
					([![:alnum:]_.:\ -]*)
						print_log error "The $1 parameter must be alphanumeric."
						exit 130
						;;
				esac
				opt_prefix="${opt_prefix#?}"
			done
			opt_prefix="$2"
			shift 2
			;;
		(-q|--quiet)
			opt_debug=''
			opt_quiet='1'
			opt_verbose=''
			shift 1
			;;
		(-r|--recursive)
			opt_recursive='1'
			shift 1
			;;
		(--send-full)
			opt_send_type='full'

			opt_send_host=$(echo "$2" | sed 's,:.*,,')
			opt_recv_pool=$(echo "$2" | sed 's,.*:,,')

			opt_send_opts="$opt_send_opts -R"
			shift 2
			;;
		(--send-incr)
			opt_send_type='incr'

			opt_send_host=$(echo "$2" | sed 's,:.*,,')
			opt_recv_pool=$(echo "$2" | sed 's,.*:,,')
			shift 2
			;;
		(--send-fallback)
			opt_send_fallback=1
			shift 1
			;;
		(--send-only)
			opt_send_only=1
			opt_do_snapshots=''
			shift 1
			;;
		(--send-opts)
			opt_send_opts="$2"
			shift 2
			;;
		(--recv-opts)
			opt_recv_opts="$2"
			shift 2
			;;
		(--send-ssh-opts)
			opt_send_ssh_opts="$2"
			shift 2
			;;
		(--send-mbuf-opts)
			opt_send_mbuf_opts="$2"
			shift 2
			;;
		(--sep)
			case "$2" in 
				([[:alnum:]_.:\ -])
					:
					;;
				('')
					print_log error "The $1 parameter must be non-empty."
					exit 131
					;;
				(*)
					print_log error "The $1 parameter must be one alphanumeric character."
					exit 132
					;;
			esac
			opt_sep="$2"
			shift 2
			;;
		(-g|--syslog)
			opt_syslog='1'
			shift 1
			;;
		(-v|--verbose)
			opt_quiet=''
			opt_verbose='1'
			shift 1
			;;
		(--pre-snapshot)
			opt_pre_snapshot="$2"
			shift 2
			;;
		(--post-snapshot)
			opt_post_snapshot="$2"
			shift 2
			;;
		(--pre-send)
			opt_pre_send="$2"
			shift 2
			;;
		(--post-send)
			opt_post_send="$2"
			shift 2
			;;
		(--destroy-only)
			opt_do_snapshots=''
			shift 1
			;;
		(--)
			shift 1
			break
			;;
	esac
done

if [ "$#" -eq '0' ]
then
	print_log error "The filesystem argument list is empty."
	exit 133
fi 

# Count the number of times '//' appears on the command line.
SLASHIES='0'
for ii in "$@"
do
	test "$ii" = '//' && SLASHIES=$(( $SLASHIES + 1 ))
done

if [ "$#" -gt '1' -a "$SLASHIES" -gt '0' ]
then
	print_log error "The // must be the only argument if it is given."
	exit 134
fi

# These are the only times that `zpool status` or `zfs list` are invoked, so
# this program for Linux has a much better runtime complexity than the similar
# Solaris implementation.

ZPOOL_STATUS=$(env LC_ALL=C zpool status 2>&1 ) \
  || { print_log error "zpool status $?: $ZPOOL_STATUS"; exit 135; }

ZFS_LIST=$(env LC_ALL=C zfs list -H -t filesystem,volume -s name \
  -o name,com.sun:auto-snapshot,com.sun:auto-snapshot:"$opt_label") \
  || { print_log error "zfs list $?: $ZFS_LIST"; exit 136; }

if [ -n "$opt_fast_zfs_list" ]
then
	SNAPSHOTS_OLD=$(env LC_ALL=C zfs list -H -t snapshot -o name -s name|grep $opt_prefix |awk '{ print substr( $0, length($0) - 14, length($0) ) " " $0}' |sort -r -k1,1 -k2,2|awk '{ print substr( $0, 17, length($0) )}') \
	  || { print_log error "zfs list $?: $SNAPSHOTS_OLD"; exit 137; }
else
	SNAPSHOTS_OLD=$(env LC_ALL=C zfs list -H -t snapshot -S creation -o name) \
	  || { print_log error "zfs list $?: $SNAPSHOTS_OLD"; exit 137; }
fi

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
	exit 138
done

# Get a list of pools that are being scrubbed.
ZPOOLS_SCRUBBING=$(echo "$ZPOOL_STATUS" | awk -F ': ' \
  '$1 ~ /^ *pool$/ { pool = $2 } ; \
   $1 ~ /^ *scan$/ && $2 ~ /scrub in progress/ { print pool }' \
  | sort ) 

# Get a list of pools that cannot do a snapshot.
ZPOOLS_NOTREADY=$(echo "$ZPOOL_STATUS" | awk -F ': ' \
  '$1 ~ /^ *pool$/ { pool = $2 } ; \
   $1 ~ /^ *state$/ && $2 !~ /ONLINE|DEGRADED/ { print pool } ' \
  | sort)

# Get a list of datasets for which snapshots are explicitly disabled.
NOAUTO=$(echo "$ZFS_LIST" | awk -F '\t' \
  'tolower($2) ~ /false/ || tolower($3) ~ /false/ {print $1}')

# If the --default-exclude flag is set, then exclude all datasets that lack
# an explicit com.sun:auto-snapshot* property. Otherwise, include them.
if [ -n "$opt_default_exclude" ]
then
	# Get a list of datasets for which snapshots are explicitly enabled.
	CANDIDATES=$(echo "$ZFS_LIST" | awk -F '\t' \
	  'tolower($2) ~ /true/ || tolower($3) ~ /true/ {print $1}')
else
	# Invert the NOAUTO list.
	CANDIDATES=$(echo "$ZFS_LIST" | awk -F '\t' \
	  'tolower($2) !~ /false/ && tolower($3) !~ /false/ {print $1}')
fi

# Initialize the list of datasets that will get a recursive snapshot.
TARGETS_RECURSIVE=''

# Initialize the list of datasets that will get a non-recursive snapshot.
TARGETS_REGULAR=''

for ii in $CANDIDATES
do
	# Qualify dataset names so variable globbing works properly.
	# Suppose ii=tanker/foo and jj=tank sometime during the loop.
	# Just testing "$ii" != ${ii#$jj} would incorrectly match.
	iii="$ii/"

	# Exclude datasets that are not named on the command line.
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

	# Exclude datasets in pools that cannot do a snapshot.
	for jj in $ZPOOLS_NOTREADY
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# Check whether the pool name is a prefix of the dataset name.
		if [ "$iii" != "${iii#$jjj}" ]
		then
			print_log info "Excluding $ii because pool $jj is not ready."
			continue 2
		fi
	done

	# Exclude datasets in scrubbing pools if the --skip-scrub flag is set.
	test -n "$opt_skip_scrub" && for jj in $ZPOOLS_SCRUBBING
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# Check whether the pool name is a prefix of the dataset name.
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

		# The --recursive switch only matters for non-wild arguments.
		if [ -z "$opt_recursive" -a "$1" != '//' ]
		then
			# Snapshot this dataset non-recursively.
			print_log debug "Including $ii for regular snapshot."
			TARGETS_REGULAR="${TARGETS_REGULAR:+$TARGETS_REGULAR	}$ii" # nb: \t
			continue 2
		# Check whether the candidate name is a prefix of any excluded dataset name.
		elif [ "$jjj" != "${jjj#$iii}" ]
		then
			# Snapshot this dataset non-recursively.
			print_log debug "Including $ii for regular snapshot."
			TARGETS_REGULAR="${TARGETS_REGULAR:+$TARGETS_REGULAR	}$ii" # nb: \t
			continue 2
		fi
	done

	for jj in $TARGETS_RECURSIVE
	do
		# Ibid regarding iii.
		jjj="$jj/"

		# Check whether any included dataset is a prefix of the candidate name.
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

# Linux lacks SMF and the notion of an FMRI event, but always set this property
# because the SUNW program does. The dash character is the default.
SNAPPROP="-o com.sun:auto-snapshot-desc='$opt_event'"

# ISO style date; fifteen characters: YYYY-MM-DD-HHMM
# On Solaris %H%M expands to 12h34.
DATE=$(date --utc +%F-%H%M)

# The snapshot name after the @ symbol.
SNAPNAME="$opt_prefix${opt_label:+$opt_sep$opt_label}-$DATE"

# The expression for matching old snapshots.  -YYYY-MM-DD-HHMM
SNAPGLOB="$opt_prefix${opt_label:+?$opt_label}????????????????"

if [ -n "$opt_do_snapshots" ]
then
	test -n "$TARGETS_REGULAR" \
	  && print_log info "Doing regular snapshots of $TARGETS_REGULAR"

	test -n "$TARGETS_RECURSIVE" \
	  && print_log info "Doing recursive snapshots of $TARGETS_RECURSIVE"

	if test -n "$opt_keep" && [ "$opt_keep" -ge "1" ]
	then
		print_log info "Destroying all but the newest $opt_keep snapshots of each dataset."
	fi
elif test -n "$opt_keep" && [ "$opt_keep" -ge "1" ]
then
	test -n "$TARGETS_REGULAR" \
	  && print_log info "Destroying all but the newest $opt_keep snapshots of $TARGETS_REGULAR"

	test -n "$TARGETS_RECURSIVE" \
	  && print_log info "Recursively destroying all but the newest $opt_keep snapshots of $TARGETS_RECURSIVE"
else
	print_log notice "Only destroying snapshots, but count of snapshots to preserve not given. Nothing to do."
fi

test -n "$opt_dry_run" \
  && print_log info "Doing a dry run. Not running these commands..."

do_snapshots "$SNAPPROP" ""   "$SNAPNAME" "$SNAPGLOB" "$TARGETS_REGULAR"
do_snapshots "$SNAPPROP" "-r" "$SNAPNAME" "$SNAPGLOB" "$TARGETS_RECURSIVE"

do_send "$SNAPNAME" "$SNAPGLOB"

print_log notice "@$SNAPNAME," \
  "$SNAPSHOT_COUNT created," \
  "$DESTRUCTION_COUNT destroyed," \
  "$WARNING_COUNT warnings."

exit 0
# }
