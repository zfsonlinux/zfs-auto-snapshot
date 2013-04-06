#!/bin/sh

# zfs-auto-snapshot for Linux and Macosx
# Automatically create, rotate, and destroy periodic ZFS snapshots.
# Copyright 2011 Darik Horn <dajhorn@vanadac.com>
#
# zfs send, hanoi rotation, macosx/linux multiplatform changes -  
# Matus Kral <matuskral@me.com>
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
opt_keep=''
opt_label='regular'
opt_prefix='zfs-auto-snap'
opt_recursive=''
opt_sep='_'
opt_setauto=''
opt_syslog=''
opt_skip_scrub=''
opt_verbose=''
opt_remove=''
opt_fallback='0'
opt_force=''
opt_sendprefix=''
opt_send='no'
opt_atonce='-I'
opt_create='0'
opt_destroy='0'
opt_rotation='rr'
opt_base='day'
opt_namechange='0'
opt_factor='1'
opt_limit='3'

# if pipe needs to be used, uncomment opt_pipe="|". arcfour or blowfish will reduce cpu load caused by ssh and mbuffer will 
# boost network bandwidth and mitigate low and high peaks during transfer
opt_sendtocmd='ssh -2 root@media -c arcfour,blowfish-cbc -i /var/root/.ssh/media.rsa'
opt_buffer=''
#opt_buffer='mbuffer -q -m 250MB |' 
opt_pipe='|'

# Global summary statistics.
DESTRUCTION_COUNT='0'
SNAPSHOT_COUNT='0'
WARNING_COUNT='0'
CREATION_COUNT='0'
SENT_COUNT='0'
KEEP=''

PLATFORM_LOC=''
PLATFORM_REM=''

# Other global variables.
SNAPSHOTS_OLD_LOC=''
SNAPSHOTS_OLD_REM=''
CREATED_TARGETS=''
ZFS_REMOTE_LIST=''
ZFS_LOCAL_LIST=''
TARGETS_DRECURSIVE=''
TARGETS_DREGULAR=''
MOUNTED_LIST_LOC=''
MOUNTED_LIST_REM=''
RC='99'

tmp_dir="/tmp/zfs-auto-snapshot.lock"

print_usage ()
{
    echo "Usage: $0 [options] [-l label] <'//' | name [name...]>

    --default-exclude  Exclude datasets if com.sun:auto-snapshot is unset.
    --remove-local=n   Remove local snapshots after successfully sent via 
                       --send-incr or --send-full but still keeps n newest
                       snapshots (this will destroy snapshots named according
                       to --prefix, but regardless of --label). Only valid for
                       round-robin rotation.
    -d, --debug        Print debugging messages.
    -e, --event=EVENT  Set the com.sun:auto-snapshot-desc property to EVENT.
    -n, --dry-run      Print actions without actually doing anything.
    -s, --skip-scrub   Do not snapshot filesystems in scrubbing pools.
    -h, --help         Print this usage message.
    -k, --keep=NUM     Keep NUM recent snapshots and destroy older snapshots.
    -l, --label=LAB    LAB is usually 'hourly', 'daily', or 'monthly' (default
                       is 'regular').
    -p, --prefix=PRE   PRE is 'zfs-auto-snap' by default.
    -q, --quiet        Suppress warnings and notices at the console.
    -c, --create       Create missing filesystems at destination.
    -i, --send-at-once Send more incremental snapshots at once in one package
                       (-i argument is passed to zfs send instead of -I). 
    --send-full=F      Send zfs full backup. F is target filesystem.
    --send-incr=F      Send zfs incremental backup. F is target filesystem.
    --sep=CHAR         Use CHAR to separate date stamps in snapshot names.
    -X, --destroy      Destroy remote snapshots to allow --send-full if 
                       destination has snapshots (needed for -F in case 
                       incremental snapshots on local and remote do not match).
                       -f is used automatically.
    -F, --fallback     Allow fallback from --send-incr to --send-full, 
                       if incremental sending is not possible (filesystem 
                       on remote just created or snapshots do not match - 
                       see -X).  
    -g, --syslog       Write messages into the system log.
    -r, --recursive    Snapshot named filesystem and all descendants.
    -R, --replication  Use zfs's replication (zfs send -R) instead of simple 
                       send over newly created snapshots (check man zfs for 
                       details). -f is used automatically. 
    -v, --verbose      Print info messages.
    -f, --force        Passes -F argument to zfs receive (e.g. makes possible 
                       to overwrite remote filesystem during --send-full).
    -o, --rotation     Round-robin (rr) or hanoi (hanoi) rotation (if -l nor -p 
                       is specified, default label will change from 'regular' 
                       to 'hanoi_regular').
    -a, --base         Base unit for hanoi cycle. Can be minute, hour, day, 
                       week, month or year (should follow your cron schedule 
                       frequency). Default base is day.
    --local-only       Parameters opt_sendtocmd and opt_buffer are not used,
                       target for --send will be local machine.
      name           Filesystem and volume names, or '//' for all ZFS datasets.
" 
}


print_log () # level, message, ...
{
	LEVEL=$1
	shift 1

	case $LEVEL in
		(eme*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.emerge "$*"
			echo Emergency: "$*" 1>&2
			;;
		(ale*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.alert "$*"
			echo Alert: "$*" 1>&2
			;;
		(cri*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.crit "$*"
			echo Critical: "$*" 1>&2
			;;
		(err*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.err "$*"
			echo Error: "$*" 1>&2
			;;
		(war*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.warning "$*"
			test -z "$opt_quiet" && echo Warning: "$*" 1>&2
			WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
			;;
		(not*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.notice "$*"
			test -z "$opt_quiet" && echo "$*"
			;;
		(inf*)
			# test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.info "$*"
			test -n "$opt_verbose" && echo "$*"
			;;
		(deb*)
			# test -n "$opt_syslog" && logger -t "$opt_prefix" -p daemon.debug "$*"
			test -n "$opt_debug" && echo Debug: "$*"
			;;
		(*)
			test -n "$opt_syslog" && logger -t "$opt_prefix" "$*"
			echo "$*" 1>&2
			;;
	esac
}


do_run () # [argv]
{
	if [ -n "$opt_dry_run" ]
	then
		echo "... Running $*"
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

do_unmount ()
{
	local TYPE="$1"
	local FLAGS="$3"
	local FSNAME="$4"
	local SNAPNAME="$5"
	local rsort_cmd='0'
	local remote_cmd=''

	case "$TYPE" in
		(remote)
			umount_list="$MOUNTED_LIST_REM" 
			remote_cmd="$opt_sendtocmd"
			;;
		(local)
			umount_list="$MOUNTED_LIST_LOC" 
			;;
	esac

	if [ -n "$SNAPNAME" ]; then
		SNAPNAME="@$SNAPNAME"
	else
		rsort_cmd='1'
	fi
	umount_list=$(printf "%s\n" "$umount_list" | grep ^"$FSNAME$SNAPNAME" )

	test -z "$umount_list" && return 0

	# reverse sort the list if unmounting filesystem and not only snapshot
	umount_list=$(printf "%s\n" "$umount_list" | awk -F'\t' '{print $2}')
	test $rsort_cmd -eq '1' && umount_list=$(printf "%s\n" "$umount_list" | sort -r)

	for kk in $umount_list; do
		print_log debug "Trying to unmount '$kk'."
		umount_cmd="umount '$kk'"
		if ! do_run "$remote_cmd" "$umount_cmd"; then return "$RC"; fi
		test "$FLAGS" != "-r" && break
	done

	return 0
}

do_delete ()
{

	local DEL_TYPE="$1"
	local FSSNAPNAME="$2"
	local FLAGS="$3"
	KEEP="$4"
	local FSNAME=$(echo $FSSNAPNAME | awk -F'@' '{print $1}')
	local SNAPNAME=$(echo $FSSNAPNAME | awk -F'@' '{print $2}')
	local remote_cmd=''

	if [ "$FSSNAPNAME" = "$FSNAME" -a "$FLAGS" = "-r" ]; then
		if [ "$opt_destroy" -ne '1' ]; then
			print_log warning "Filesystem $FSNAME destroy requested, but option -X not specified. Aborting."
			return 1
		else
			KEEP='0'
		fi
	fi

	KEEP=$(( $KEEP - 1 ))
	if [ "$KEEP" -le '0' ]
	then
		if do_unmount "$DEL_TYPE" "" "$FLAGS" "$FSNAME" "$SNAPNAME"; then
			if [ "$DEL_TYPE" = "remote" ]; then
				remote_cmd="$opt_sendtocmd"
			fi
			if do_run "$remote_cmd" "zfs destroy $FLAGS '$FSSNAPNAME'"; then
				DESTRUCTION_COUNT=$(( $DESTRUCTION_COUNT + 1 ))
			fi
		fi
	fi

	return "$RC"
}

is_member ()
{
	local ARRAY="$1"
	local MEMBER="$2"
	local ISMEMBER='1'
	local mm=''

	for mm in $ARRAY; do
		if test "$mm" = "$MEMBER"; then
			ISMEMBER='0'
			break
		fi
	done

	return "$ISMEMBER"
}

do_send ()
{
	local SENDTYPE="$1"
	local SNAPFROM="$2"
	local SNAPTO="$3"
	local SENDFLAGS="$4"
	local REMOTEFS="$5"
	local list_child=''
	local lq=''

	if [ "$SENDFLAGS" = "-R" -a "$SENDTYPE" = "full" ]; then
		# for full send with -R, target filesystem must be with no snapshots (including snapshots on child filesystems)
		list_child=$(printf "%s\n" "$SNAPSHOTS_OLD_REM" | grep ^"$REMOTEFS/" )
	fi
	if [ "$SENDTYPE" = "full" ]; then
		list_child=$(printf "%s\n%s\n" "$list_child" $(printf "%s\n" "$SNAPSHOTS_OLD_REM" | grep ^"$REMOTEFS@" ) )
	fi

	for ll in $list_child; do
		if [ "$opt_destroy" -eq '1' ]; then
			if do_delete "remote" "$ll" ""; then
				continue
			fi
		fi
		print_log debug "Can't destroy remote objects $REMOTEFS ($ll). Can't continue with send-full. -X allowed?"
		return 1
	done
	
	test -n "$opt_buffer" && lq="'"

	test $SENDTYPE = "incr" && do_run "zfs send " "$SENDFLAGS" "$opt_atonce  $SNAPFROM   $SNAPTO" "$opt_pipe" "$opt_sendtocmd" "$lq$opt_buffer zfs recv  $opt_force -u $REMOTEFS$lq"
	test $SENDTYPE = "full" && do_run "zfs send " "$SENDFLAGS" "$SNAPTO" "$opt_pipe" "$opt_sendtocmd" "$lq$opt_buffer zfs recv $opt_force -u $REMOTEFS$lq"

	return "$RC"
}

delete_rotation_hanoi ()
{

	local SND_RC="$1"
	local FALLBACK="$2"
	local FSNAME="$3"
	local GLOB="$4"
	local FLAGS="$5"
	local SNAPNAME="$6"

	local base_minute=$((60 * $opt_factor ))
	local base_hour=$(($base_minute * 60))
	local base_day=$(($base_hour * 24))
	local base_week=$(($base_day * 7))
	local base_month=$(($base_day * 31))
	local base="base_$opt_base"

	local opt_hbase=$(eval echo \$$base)

	classify ()
	{
		rec () 
		{
			local class='0'
			local nr="$1"

			while test $(( 1 << $(($class)) )) -le $(($nr>>1)); do
				class=$(($class+1))
			done
			bla=$(($nr - $(( 1 << $(($class)) )) ))
			test "$bla" -eq '0' && echo $(($class+1)) || rec "$bla" 
		}

		local creation="$1"
		local creation_std=''
		local snapdate=''

		case $PLATFORM_LOC in
			(Linux)
				snapdate=$(echo "$creation" | awk -F'-' '{print $1"-"$2"-"$3" "$4}')
				creation_std=$(($(env LC_ALL=C date -d "$snapdate" +%s ) /  $opt_hbase ))
				;;
			(Darwin)
				creation_std=$(($(env LC_ALL=C date -j -f "%F-%H%M" "$creation" +%s ) / $opt_hbase ))
				;;
		esac

		echo $(rec $creation_std)
	}

	destroy ()
	{
		local dlist="$1"
		local dprefix="$2"
		local dtype="$3"
		local dFSNAME="$4"
		local dFLAGS="$5"
		local class=''
		local previous_class='0'

		tmp_table=$(printf "%s\n" "$dlist" |\
			grep -e ^"$dprefix$FSNAME@$opt_prefix.$opt_label" | 
				while read name; do
					echo "$(classify ${name#$dprefix$FSNAME@$opt_prefix${opt_label:+?$opt_label}?}) $name"  
				done | sort -k 1rn -k 2r | awk '{print $1"\t"$2}') 

		for mm in $tmp_table
		do
			class=$(echo "$mm" | awk -F'\t' '{print $1}')
			if [ "$class" -eq "$previous_class" ]; then
				do_delete "$dtype" $(echo "$mm" | awk -F'\t' '{print $2}')  "$FLAGS"
			fi
			previous_class="$class"
		done

	}

	destroy "$(printf "%s\n%s\n" "$SNAPSHOTS_OLD_LOC" "$FSNAME@$SNAPNAME" )" "" "local" "$FSNAME" "$FLAGS"
	if [ "$SND_RC" -eq '0' ] && [ "$opt_send" != "no" ]; then
		destroy "$(printf "%s\n%s\n" "$SNAPSHOTS_OLD_REM" "$opt_sendprefix/$FSNAME@$SNAPNAME" )" "$opt_sendprefix/" "remote" "$FSNAME" "$FLAGS"		
	fi

}

delete_rotation_rr ()
{

	local SND_RC="$1"
	local FALLBACK="$2"
	local FSNAME="$3"
	local GLOB="$4"
	local FLAGS="$5"

	# Retain at most $opt_keep number of old snapshots of this filesystem,
	# including the one that was just recently created.
	if [ -z "$opt_keep" ]
	then
		print_log debug "Number of snapshots not specified. Keeping all."
		continue
	elif [ "$opt_send" != "no" ] && [ "$SND_RC" -ne '0' ]
	then
		print_log debug "Sending of filesystem was requested, but send failed. Ommiting destroy procedures."
		continue
	elif [ "$opt_send" != "no" -a -n "$opt_remove" ]
	then
		KEEP="$opt_remove"
	else
		KEEP="$opt_keep"
	fi
	print_log debug "Destroying local snapshots, keeping $KEEP."			

	# ASSERT: The old snapshot list is sorted by increasing age.
	for jj in $SNAPSHOTS_OLD_LOC
	do
		# Check whether this is an old snapshot of the filesystem.
		test -z "${jj#$FSNAME@$GLOB}" -o -z "${jj##$FSNAME@$opt_prefix*}" -a -n "$opt_remove" -a "$opt_send" != "no" && do_delete "local" "$jj" "$FLAGS" "$KEEP"
	done

	if [ "$opt_send" = "no" ]
	then
		print_log debug "No sending option specified, skipping remote snapshot removal."
		continue
	elif [ "$sFLAGS" = "-R" ]
	then
		print_log debug "Replication specified, remote snapshots were removed while sending."
		continue
	elif [ "$opt_destroy" -eq '1' -a "$FALLBACK" -ne '0' -o "$opt_send" = "full" ]
	then
		print_log debug "Sent full copy, all remote snapshots were already destroyed."
		continue
	else
		KEEP="$opt_keep"
		print_log debug "Destroying remote snapshots, keeping $KEEP."
	fi

	# ASSERT: The old snapshot list is sorted by increasing age.
	for jj in $SNAPSHOTS_OLD_REM
	do
		# Check whether this is an old snapshot of the filesystem.
		test -z "${jj#$opt_sendprefix/$FSNAME@$GLOB}" && do_delete "remote" "$jj" "$FLAGS" "$KEEP" 
	done

}

do_snapshots () # properties, flags, snapname, oldglob, [targets...]
{
	local PROPS="$1"
	local sFLAGS="$2"
	local NAME="$3"
	local GLOB="$4"
	local TARGETS="$5"
	local LAST_REMOTE=''

	local FALLBACK=''

	if test "$sFLAGS" = '-R'; then
		FLAGS='-r'
		SNexp='.*'
	else
		FLAGS=''
	fi

	for ii in $TARGETS
	do
		FALLBACK='0'
		SND_RC='1'

		print_log debug "--> Snapshooting $ii"

		if ! do_run "zfs snapshot $PROPS $FLAGS '$ii@$NAME'" 
		then
			continue
		fi
		SNAPSHOT_COUNT=$(( $SNAPSHOT_COUNT + 1 ))

		if [ "$opt_send" = "incr" ]
		then

			LAST_REMOTE=$(printf "%s\n" "$SNAPSHOTS_OLD_REM" | grep ^"$opt_sendprefix/$ii@" | grep -m1 . | awk -F'@' '{print $2}')

			# in case of -R and incremental send, receiving side needs to have $LAST_REMOTE snapshot for each replicated filesystem
			if [ "$FLAGS" = "-r" ]; then
				snaps_needed=$(( $(printf "%s\n" "$ZFS_LOCAL_LIST" | grep -c ^"$ii/") + 1 )) 
			else
				snaps_needed='1'
			fi

			# remote filesystem just created. if -R run
			if is_member "$CREATED_TARGETS" "$opt_sendprefix/$ii"
			then  
				FALLBACK='2'
			elif [ -z "$LAST_REMOTE" ]
			then
				# no snapshot on remote
				FALLBACK='1'
			elif [ "$snaps_needed" -ne $(printf "%s" "$SNAPSHOTS_OLD_REM" | grep -c -e ^"$opt_sendprefix/$ii$SNexp@$LAST_REMOTE" ) -o \
				"$snaps_needed" -ne $(printf "%s" "$SNAPSHOTS_OLD_LOC" | grep -c -e ^"$ii$SNexp@$LAST_REMOTE" ) ] 
			then  
				FALLBACK='3'
			else
				FALLBACK='0'
			fi

			case "$FALLBACK" in
				(1)
					print_log info "Going back to full send, no snapshot exists at destination: $ii"
					;;
				(2)
					print_log info "Going back to full send, remote filesystem was just created: $ii"
					;;
				(3)
					if [ "$FLAGS" = "-r" ]; then
						print_log info "Going back to full send, last snapshot on remote is not the last one for whole recursion: $opt_sendprefix/$ii@$LAST_REMOTE"
					else
						print_log info "Going back to full send, last snapshot on remote is not available on local: $opt_sendprefix/$ii@$LAST_REMOTE"
					fi
					;;
				(0)
					do_send "incr" "$ii@$LAST_REMOTE" "$ii@$NAME" "$sFLAGS" "$opt_sendprefix/$ii" 
					SND_RC="$?"
					;;
			esac
		fi

		if [ "$opt_send" = "full" -o "$FALLBACK" -ne '0' -a "$opt_fallback" -eq '1' ]; then
			do_send "full" "" "$ii@$NAME" "$sFLAGS" "$opt_sendprefix/$ii"
			SND_RC="$?"
		fi
		test "$SND_RC" -eq '0' && SENT_COUNT=$(( $SENT_COUNT + 1 ))

		case $opt_rotation in 
			(rr)
				delete_rotation_rr "$SND_RC" "$FALLBACK" "$ii" "$GLOB" "$FLAGS"
				;;
			(hanoi)
				delete_rotation_hanoi "$SND_RC" "$FALLBACK" "$ii" "$GLOB" "$FLAGS" "$NAME"
				;;
		esac

	done
}

do_getmountedfs ()
{

	local MOUNTED_TYPE="$1"
	local MOUNTED_LIST=''
	local remote_cmd=''

	case "$MOUNTED_TYPE" in
		(remote)
			remote_cmd="$opt_sendtocmd"
			PLATFORM="$PLATFORM_REM"
			;;
		(local)
			PLATFORM="$PLATFORM_LOC"
			;;
	esac

	case "$PLATFORM" in
		(Linux)
			MOUNTED_LIST=$(eval $remote_cmd cat /proc/mounts | grep zfs | awk -F' ' '{OFS="\t"}{ORS="\n"}{print $1,$2}' )
			;;
		(Darwin)
			MOUNTED_LIST=$(printf "%s\n%s\n" $(eval $remote_cmd zfs mount | awk -F' ' '{OFS="\t"}{ORS="\n"}{print $1,$2}') \
				$(eval $remote_cmd mount -t zfs | grep @ | awk -F' ' '{OFS="\t"}{ORS="\n"}{print $1,$3}') )
			;;
	esac

	printf "%s\n" "$MOUNTED_LIST" | sort  
}

do_createfs ()
{

	local FS="$1"

	for ii in $FS; do

		print_log debug "checking: $opt_sendprefix/$ii"

		if ! is_member "$ZFS_REMOTE_LIST" "$opt_sendprefix/$ii" -eq 0
		then
			print_log debug "creating: $opt_sendprefix/$ii"

			if do_run "$opt_sendtocmd" "zfs create -p -o canmount=off -o snapdir=hidden $opt_sendprefix/$ii"
			then 
				CREATION_COUNT=$(( $CREATION_COUNT + 1 ))
				CREATED_TARGETS=$(printf "%s\n%s\n" "$CREATED_TARGETS" "$opt_sendprefix/$ii" )
			fi
		fi
	done

}

# main ()
# {

PLATFORM_LOC=`uname`
case "$PLATFORM_LOC" in 
	(Linux)
		getopt_cmd='getopt'
		;;
	(Darwin)
		# macports path as default. Homebrew as fallback
		getopt_cmd='/opt/local/bin/getopt'
		if [ ! -f $getopt_cmd ]; then
			getopt_cmd='/usr/local/opt/gnu-getopt/bin/getopt'
		fi
		;;
	(*)
		print_log error "Local system not known ($PLATFORM_LOC) - needs one of Darwin, Linux. Exiting."
		exit 300
		;;
esac

GETOPT=$("$getopt_cmd" \
	--longoptions=default-exclude,dry-run,skip-scrub,recursive,send-atonce,rotation:,local-only \
	--longoptions=event:,keep:,label:,prefix:,sep:,create,fallback,rollback,base:,factor: \
	--longoptions=debug,help,quiet,syslog,verbose,send-full:,send-incr:,remove-local:,destroy \
	--options=dnshe:l:k:p:rs:qgvfixcXFRba:o: \
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
		(-c|--create)
			opt_create='1'
			shift 1
			;;
		(-x|--default-exclude)
			opt_default_exclude='1'
			shift 1
			;;
		(-e|--event)
			if [ "${#2}" -gt '1024' ]
			then
				print_log error "The $1 parameter must be less than 1025 characters."
				exit 239
			elif [ "${#2}" -gt '0' ]
			then
				opt_event="$2"
			fi
			shift 2
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
		(--local-only)
			opt_sendtocmd=''
			opt_buffer=''
			shift 1
			;;
		(-k|--keep)
			if ! test "$2" -gt '0' 2>/dev/null
			then
				print_log error "The $1 parameter must be a positive integer."
				exit 229
			fi
			opt_keep="$2"
			shift 2
			;;
		(-a|--base)
			case $2 in
				(day|week|month|hour|minute)
					opt_base="$2"
					;;
				(*)
					print_log error "The $1 parameter must be one of: minute, hour, day, week, month, year."
					exit 244
					;;
			esac
			shift 2
			;;
		(-o|--rotation)
			case $2 in
				(hanoi|rr)
					opt_rotation="$2"
					;;
				(*)
					print_log error "Rotation must be one of hanoi or rr
					."	
					exit 245
					;;
			esac
			shift 2
			;;
		(-l|--label)
			opt_label="$2"
			opt_namechange='1'
			shift 2
			;;
		(-p|--prefix)
			opt_prefix="$2"
			while test "${#opt_prefix}" -gt '0'
			do
				case $opt_prefix in
					([![:alnum:]_.:\ -]*)
						print_log error "The $1 parameter must be alphanumeric."
						exit 230
						;;
				esac
				opt_prefix="${opt_prefix#?}"
			done
			opt_prefix="$2"
			opt_namechange='1'
			shift 2
			;;
		(--factor)
			opt_factor="$2"
			shift 2
			;;
		(-q|--quiet)
			opt_debug=''
			opt_quiet='1' 
			opt_verbose=''
			shift 1
			;;
		(-r|--recursive)
			opt_recursive=' '
			shift 1
			;;
		(-R|--replication)
			opt_recursive='-R'
			opt_force='-F'
			shift 1
			;;
		(-X|--destroy)
			opt_destroy='1'
			opt_force='-F'
			shift 1
			;;
		(-F|--fallback)
			opt_fallback='1'
			shift 1
			;;
		(--sep)
			case "$2" in 
				([[:alnum:]_.:\ -])
					:
					;;
				('')
					print_log error "The $1 parameter must be non-empty."
					exit 231
					;;
				(*)
					print_log error "The $1 parameter must be one alphanumeric character."
					exit 232
					;;
			esac
			opt_sep="$2"
			shift 2
			;;
		(--send-full)
			if [ -n "$opt_sendprefix" ]; then
				print_log error "Only one of --send-incr and --send-full must be specified."
				exit 239
			fi
			if [ -z "$2" ]; then
				print_log error "Target filesystem needs to be specified with --send-full."
				exit 243
			fi
			opt_sendprefix="$2"
			opt_send='full'			
			shift 2
			;;
		(--send-incr)
			opt_sendincr="$2"
			if [ -n "$opt_sendprefix" ]; then
				print_log error "Only one of --send-incr and --send-full must be specified."
				exit 240
			fi
			if [ -z "$2" ]; then
				print_log error "Target filesystem needs to be specified with --send-incr."
				exit 242
			fi
			opt_sendprefix="$2"
			opt_send='incr'			
			shift 2
			;;
		(-g|--syslog)
			opt_syslog='1'
			shift 1
			;;
		(-i|--send-atonce)
			opt_atonce='-i'
			shift 1
			;;			
		(--remove-local)
			if ! test "$2" -gt '0' 2>/dev/null
			then
				print_log error "The $1 parameter must be a positive integer."
				exit 241
			fi
			opt_remove="$2"
			shift 2
			;;
		(-v|--verbose)
			opt_quiet=''
			opt_verbose='1'
			shift 1
			;;
		(-f|--force|-b|--rollback)
			opt_force='-F'
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

# ISO style date; fifteen characters: YYYY-MM-DD-HHMM
# On Solaris %H%M expands to 12h34.
DATE=$(date +%F-%H%M)

COUNTER='0'
while true; do
	if do_run "mkdir '${tmp_dir}'"; then break; fi  
	print_log error "another copy is running ... $COUNTER"
	test "$COUNTER" -gt '11' && exit 99
	sleep 5
	COUNTER=$(( $COUNTER + 1 ))
done  
trap "rm -fr '${tmp_dir}'" INT TERM EXIT

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

ZPOOL_STATUS=$(env LC_ALL=C zpool status 2>&1 )\
	|| { print_log error "zpool status $?: $ZPOOL_STATUS"; exit 135; }

ZFS_LIST=$(env LC_ALL=C zfs list -H -t filesystem,volume -s name\
	-o name,com.sun:auto-snapshot,com.sun:auto-snapshot:"$opt_label",mountpoint,canmount,snapdir)\
	|| { print_log error "zfs list $?: $ZFS_LIST"; exit 136; }

ZFS_LOCAL_LIST=$(echo "$ZFS_LIST" | awk -F'\t' '{print $1}')

# Verify that each argument is a filesystem or volume.
for ii in "$@"
do
	test "$ii" = '//' && continue 1
	for jj in $ZFS_LOCAL_LIST
	do
	   test "$ii" = "$jj" && continue 2
	done
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
	| sort )

# Get a list of datasets for which snapshots are not explicitly disabled.
CANDIDATES=$(echo "$ZFS_LIST" | awk -F '\t' \
	'tolower($2) !~ /false/ && tolower($3) !~ /false/ {print $1}' )

# If the --default-exclude flag is set, then exclude all datasets that lack
# an explicit com.sun:auto-snapshot* property. Otherwise, include them.
if [ -n "$opt_default_exclude" ]
then
	# Get a list of datasets for which snapshots are not explicitly enabled.
	NOAUTO=$(echo "$ZFS_LIST" | awk -F '\t' \
		'tolower($2) !~ /true/ && tolower($3) !~ /true/ {print $1}')
else
	# Get a list of datasets for which snapshots are explicitly disabled.
	NOAUTO=$(echo "$ZFS_LIST" | awk -F '\t' \
		'tolower($2) ~ /false/ || tolower($3) ~ /false/ {print $1}')
fi

# Initialize the list of datasets that will get a recursive snapshot.
TARGETS_DRECURSIVE=''
TARGETS_TMP_RECURSIVE=''

# Initialize the list of datasets that will get a non-recursive snapshot.
TARGETS_DREGULAR=''

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
		if [ "$jj" = '//' -o "$jj" = "$ii" -o -n "$opt_recursive" -a -z "${ii##$jj/*}" ]
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

	noauto_parent='0'
	for jj in $NOAUTO
	do
		# Ibid regarding iii.
		jjj="$jj/"

		if [ "$jjj" = "$iii" ]
		then
			continue 2
			# Check whether the candidate name is a prefix of any excluded dataset name.
		elif [ "$jjj" != "${jjj#$iii}" ]
		then
			noauto_parent='1' && break
		fi
	done

	# not scrubbing 
	if [ -z "$opt_recursive" -a "$1" != '//' -o "$noauto_parent" = '1' ]
	then
		print_log debug "Including $ii for regular snapshot."
		TARGETS_DREGULAR=$(printf "%s\n%s\n" "$TARGETS_DREGULAR" "$ii" )
		continue
	fi

	for jj in $TARGETS_TMP_RECURSIVE
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
	TARGETS_TMP_RECURSIVE=$( printf "%s\n%s\n" $TARGETS_TMP_RECURSIVE "$ii" )

done

# Linux lacks SMF and the notion of an FMRI event, but always set this property
# because the SUNW program does. The dash character is the default.
SNAPPROP="-o com.sun:auto-snapshot-desc='$opt_event'"

# if hanoi rotation was requested but prefix or label wasn't changed from default, change label to hanoi to avoid mixing of those backup sets.
if [ "$opt_namechange" -eq '0' ] && [ "$opt_rotation" = "hanoi" ]; then
	opt_label="hanoi_regular"
fi

# The snapshot name after the @ symbol.
SNAPNAME="$opt_prefix${opt_label:+$opt_sep$opt_label-$DATE}"

# The expression for matching old snapshots.  -YYYY-MM-DD-HHMM
SNAPGLOB="$opt_prefix${opt_label:+?$opt_label}????????????????"

msg_to_log="Using $opt_rotation type rotation, with params keep: $opt_keep" 
if test "$opt_rotation" = "hanoi"; then
	msg_to_log=$(echo "$msg_to_log," "base: $opt_base")
fi
print_log debug "$msg_to_log."

test -n "$TARGETS_DREGULAR" && \
	print_log info "Doing regular snapshots of $(echo $TARGETS_DREGULAR)"

test -n "$TARGETS_TMP_RECURSIVE" && \
	print_log info "Doing recursive snapshots of $(echo $TARGETS_TMP_RECURSIVE)"

SNAPSHOTS_OLD_LOC=$(env LC_ALL=C zfs list -r -H -t snapshot -S creation -o name $(echo "$TARGETS_DREGULAR") $(echo "$TARGETS_TMP_RECURSIVE") ) \
	|| { print_log error "zfs list $?: $SNAPSHOTS_OLD_LOC"; exit 137; }

test -n "$opt_dry_run" \
	&& print_log info "Doing a dry run. Not running these commands..."

# expand FS list if replication is not used 
if [ "$opt_recursive" = ' ' -o "$1" = "//" ]
then
	for ii in $TARGETS_TMP_RECURSIVE; do TARGETS_DRECURSIVE=$(printf "%s\n%s\n%s\n" "$TARGETS_DRECURSIVE" $(printf "$ii\n") $(printf "%s\n" "$ZFS_LOCAL_LIST" | grep ^"$ii/") ); done
else
	TARGETS_DRECURSIVE="$TARGETS_TMP_RECURSIVE"
fi

MOUNTED_LIST_LOC=$(eval do_getmountedfs "local")

# initialize remote system parameters, filesystems, mounts and snapshots
if [ "$opt_send" != "no" ]
then
	PLATFORM_REM=$(eval "$opt_sendtocmd" "uname")

	case "$PLATFORM_REM" in 
		(Linux|Darwin)
			;;
		(*)
			print_log error "Remote system not known ($PLATFORM_REM) - needs one of Darwin, Linux. Exiting."
			exit 301
			;;
	esac
	
	if [ -n $opt_limit ]; then
		runs='1'
		condition='1'
		while [ $condition -eq '1' ]; do
			load=$(eval "$opt_sendtocmd" "uptime")
			load=$(echo ${load##*"load average"}} | awk '{print $2}' | awk -F'.' '{print $1}')
			if [ $load -ge $opt_limit -a $runs -lt '3' ]; then
				print_log warning "Over load limit on remote machine. Going for sleep for 5 minutes. (run #$runs, load still $load)"
				sleep 300
			else
				if [ $load -ge $opt_limit ]; then
				    opt_send="no"
				    opt_keep=''
				    print_log warning "Over load limit on remote machine. Will not send to remote. (run #$runs, load still $load)"
                fi
				condition='0'
			fi
			runs=$(( $runs + 1 ))
		done
	fi
fi

if [ "$opt_send" != "no" ]; then
	MOUNTED_LIST_REM=$(eval do_getmountedfs "remote")

	ZFS_REMOTE_LIST=$(eval "$opt_sendtocmd" zfs list -H -t filesystem,volume -s name -o name) \
		|| { print_log error "$opt_sendtocmd zfs list $?: $ZFS_REMOTE_LIST"; exit 139; }

	if [ "$opt_create" -eq '1' ]; then
		do_createfs "$TARGETS_DREGULAR"
		do_createfs "$TARGETS_DRECURSIVE"
	fi
	
	SNAPSHOTS_OLD_REM=$(eval "$opt_sendtocmd" zfs list -r -H -t snapshot -S creation -o name "$opt_sendprefix") \
		|| { print_log error "zfs remote list $?: $SNAPSHOTS_OLD_REM"; exit 140; }
fi


do_snapshots "$SNAPPROP" "" "$SNAPNAME" "$SNAPGLOB" "$TARGETS_DREGULAR"
do_snapshots "$SNAPPROP" "$opt_recursive" "$SNAPNAME" "$SNAPGLOB" "$TARGETS_DRECURSIVE"

print_log notice "@$SNAPNAME," \
	"$SNAPSHOT_COUNT created snapshots," \
	"$SENT_COUNT sent snapshots," \
	"$DESTRUCTION_COUNT destroyed," \
	"$CREATION_COUNT created filesystems," \
	"$WARNING_COUNT warnings."

exit 0
# }
