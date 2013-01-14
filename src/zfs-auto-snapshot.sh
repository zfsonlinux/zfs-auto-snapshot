#!/bin/bash

# zfs-auto-snapshot for Linux and Macosx
# Automatically create, rotate, and destroy periodic ZFS snapshots.
# Copyright 2011 Darik Horn <dajhorn@vanadac.com>
# zfs send options and macosx relevant changes by Matus Kral <matuskral@me.com>
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

# if pipe needs to be used, uncomment opt_pipe="|"
opt_sendtocmd='ssh -1 root@media -i /var/root/.ssh/media.rsa1'
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
declare -a SNAPSHOTS_OLD_LOC=('')
declare -a SNAPSHOTS_OLD_REM=('')
declare -a CREATED_TARGETS=('')
declare -a ZFS_REMOTE_LIST=('')
declare -a ZFS_LOCAL_LIST=('')
declare -a TARGETS_DRECURSIVE=('')
declare -a TARGETS_DREGULAR=('')
declare -a MOUNTED_LIST_LOC=('')
declare -a MOUNTED_LIST_REM=('')
declare -i RC=99

tmp_file_prefix="/tmp/zfs-auto-snapshot.XXXXXXXX"
set -o pipefail

print_usage ()
{
	echo "Usage: $0 [options] [-l label] <'//' | name [name...]>
  --default-exclude  Exclude datasets if com.sun:auto-snapshot is unset.
  --remove-local=n   Remove local snapshots after successfully sent via --send-incr or --send-full but still keeps n newest snapshots
                     (this will destroy snapshots named according to --prefix, but regardless of --label).
  -d, --debug        Print debugging messages.
  -e, --event=EVENT  Set the com.sun:auto-snapshot-desc property to EVENT.
  -n, --dry-run      Print actions without actually doing anything.
  -s, --skip-scrub   Do not snapshot filesystems in scrubbing pools.
  -h, --help         Print this usage message.
  -k, --keep=NUM     Keep NUM recent snapshots and destroy older snapshots.
  -l, --label=LAB    LAB is usually 'hourly', 'daily', or 'monthly' (default is 'regular').
  -p, --prefix=PRE   PRE is 'zfs-auto-snap' by default.
  -q, --quiet        Suppress warnings and notices at the console.
  -c, --create       Create missing filesystems at destination.
  -i, --send-at-once Send more incremental snapshots at once in one package (-i argument is passed to zfs send instead of -I). 
      --send-full=F  Send zfs full backup. F is target filesystem.
      --send-incr=F  Send zfs incremental backup. F is target filesystem.
      --sep=CHAR     Use CHAR to separate date stamps in snapshot names.
  -X, --destroy      Destroy remote snapshots to allow --send-full if destination has snapshots (needed for -F in case incremental
                     snapshots on local and remote do not match).
  -F, --fallback     Allow fallback from --send-incr to --send-full, if incremental sending is not possible (filesystem on remote just
                     created or snapshots do not match - see -X).  
  -g, --syslog       Write messages into the system log.
  -r, --recursive    Snapshot named filesystem and all descendants.
  -R, --replication  Use zfs's replication (zfs send -R) instead of simple send over newly created snapshots (check man zfs for details).
                     -f is used automatically. 
  -v, --verbose      Print info messages.
  -f, --force        Passes -F argument to zfs receive
      name           Filesystem and volume names, or '//' for all ZFS datasets.
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
			WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
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
		print_log notice "... running: $*"
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
            umount_list=( "${MOUNTED_LIST_REM[@]}" ) 
			remote_cmd="$opt_sendtocmd"
			;;
		(local)
            umount_list=( "${MOUNTED_LIST_LOC[@]}" )
			;;
	esac

    if [ -n "$SNAPNAME" ]; then
        SNAPNAME="@$SNAPNAME"
    else
		rsort_cmd='1'
    fi
    umount_list=( $(printf "%s\t%s\n" "${umount_list[@]}" | grep ^"$FSNAME$SNAPNAME" ) )

    test -z "$umount_list" && return 0

	# reverse sort the list if unmounting filesystem and not only snapshot
    umount_list=($(printf "%s\t%s\n" "${umount_list[@]}" | awk -F'\t' '{print $2}'))
    test $rsort_cmd -eq '1' && umount_list=($(printf "%s\n" "${umount_list[@]}"))

	for kk in ${umount_list[@]}; do
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
    local ARRAY=(${1})
    local MEMBER="$2"
    declare -i ISMEMBER=0
    
    result=$(printf "%s\n" "${ARRAY[@]}"| grep -m1 -x "$MEMBER")
    if [ -n "$result" -a -z "${result#$MEMBER}" ]; then ISMEMBER=1; fi
    
    return "$ISMEMBER"
}

do_send ()
{
    local SENDTYPE="$1"
    local SNAPFROM="$2"
    local SNAPTO="$3"
    local SENDFLAGS="$4"
    local REMOTEFS="$5"
    local list_child=('')

    if [ "$SENDFLAGS" = "-R" -a "$SENDTYPE" = "full" ]; then
        # for full send with -R, target filesystem must be without snapshots including chilren as well
        list_child=($(printf "%s\n" "${SNAPSHOTS_OLD_REM[@]}" | grep ^"$REMOTEFS" | grep @))
        if [ "$SENDTYPE" = "full" ]; then
            list_child=( "${list_child[@]}" $(printf "%s\n" "${ZFS_REMOTE_LIST[@]}" | grep ^"$REMOTEFS" | sort -r ))
        fi
    elif [ "$SENDTYPE" = "full" ]; then
        list_child=( $(printf "%s\n" "${SNAPSHOTS_OLD_REM[@]}" | grep ^"$REMOTEFS@" ) )
    fi
        
    for ll in ${list_child[@]}; do
        if do_delete "remote" "$ll" ""; then
            continue
        fi
        print_log debug "Can't destroy remote filesystem $REMOTEFS ($ll). Can't continue with send-full."
        return 1
    done

    test $SENDTYPE = "incr" && do_run "zfs send " "$SENDFLAGS" "$opt_atonce  $SNAPFROM   $SNAPTO" "$opt_pipe" "$opt_sendtocmd" "zfs recv  $opt_force -u $REMOTEFS"
    test $SENDTYPE = "full" && do_run "zfs send " "$SENDFLAGS" "$SNAPTO" "$opt_pipe" "$opt_sendtocmd" "zfs recv $opt_force -u $REMOTEFS"

    return "$RC"
}

do_snapshots () # properties, flags, snapname, oldglob, [targets...]
{
	local PROPS="$1"
	local sFLAGS="$2"
	local NAME="$3"
	local GLOB="$4"
	local TARGETS=(${5})
	local KEEP=''
	local LAST_REMOTE=''

    if test "$sFLAGS" = '-R'; then
        FLAGS='-r'
        SNexp='.*'
    else
        FLAGS=''
    fi

	for ii in ${TARGETS[@]}
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

            LAST_REMOTE=$(printf "%s\n" ${SNAPSHOTS_OLD_REM[@]} | grep ^$opt_sendprefix/$ii@ | grep -m1 . | awk -F'@' '{print $2}')

			# remote filesystem just created. if -R run
			if ! is_member "${CREATED_TARGETS[*]}" "$opt_sendprefix/$ii"
            then  
				FALLBACK='2'
			elif [ -z "$LAST_REMOTE" ]
			then
				# no snapshot on remote
				FALLBACK='1'
			# last snapshot on remote is no more available on local, this applies both for -r and non -r runs
			elif [ $(printf "%s\n" "${SNAPSHOTS_OLD_REM[@]}" | grep -c -e ^$opt_sendprefix/$ii$SNexp@$LAST_REMOTE ) -ne $(printf "%s\n" "${SNAPSHOTS_OLD_LOC[@]}" | grep -c -e ^$ii$SNexp@$LAST_REMOTE ) ]
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
					print_log info "Going back to full send, last snapshot on remote is not available on local: $opt_sendprefix/$ii@$LAST_REMOTE"
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
		for jj in ${SNAPSHOTS_OLD_LOC[@]}
		do
			# Check whether this is an old snapshot of the filesystem.
			test -z "${jj#$ii@$GLOB}" -o -z "${jj##$ii@$opt_prefix*}" -a -n "$opt_remove" \
				-a "$opt_send" != "no" && do_delete "local" "$jj" "$FLAGS"
		done

		if [ "$opt_send" = "no" ]
		then
			print_log debug "No sending option specified, skipping remote snapshot removal."
			continue
		elif [ "$sFLAGS" = "-R" ]
		then
			print_log debug "Replication specified, snapshots were removed while sending."
			continue
		elif [ "$opt_destroy" -eq '1' -a "$FALLBACK" -ne '0' -o "$opt_send" = "full" ]
		then
			print_log debug "Sent full copy, all remote snapshots were already destroyed."
			continue
		else
			KEEP="$opt_keep"
			print_log debug "Destroying remote snapshots, keeping only $KEEP."
		fi

		# ASSERT: The old snapshot list is sorted by increasing age.
		for jj in ${SNAPSHOTS_OLD_REM[@]}
		do
			# Check whether this is an old snapshot of the filesystem.
			test -z "${jj#$opt_sendprefix/$ii@$GLOB}" && do_delete "remote" "$jj" "$FLAGS" 
		done

	done
}

do_getmountedfs ()
{

    local MOUNTED_TYPE="$1"
    local MOUNTED_LIST
    local remote_cmd=''

    case "$MOUNTED_TYPE" in
        (remote)
            remote_cmd="$opt_sendtocmd"
            PLATFORM="$PLATFORM_REM"
            ;;
        (local)
            remote_cmd=""
            PLATFORM="$PLATFORM_LOC"
            ;;
    esac

    case "$PLATFORM" in
        (Linux)
            MOUNTED_LIST=( $(eval $remote_cmd cat /proc/mounts | grep zfs | awk -F' ' '{OFS="\t"}{print $1,$2}' ) )
            ;;
        (Darwin)
            MOUNTED_LIST=( $(eval $remote_cmd zfs mount | awk -F' ' '{OFS="\t"}{print $1,$2}') $(eval $remote_cmd mount -t zfs | grep @ | awk -F' ' '{OFS="\t"}{print $1,$3}') )
            ;;
    esac

    printf "%s\t%s\n" "${MOUNTED_LIST[@]}" | sort  
}

do_createfs ()
{

	local FS=(${1})

	for ii in ${FS[@]}; do

		print_log debug "checking: $opt_sendprefix/$ii"

		if is_member "${ZFS_REMOTE_LIST[*]}" "$opt_sendprefix/$ii" -eq 0
		then
			print_log debug "creating: $opt_sendprefix/$ii"

			if do_run "$opt_sendtocmd" "zfs create $opt_sendprefix/$ii"
			then 
				CREATION_COUNT=$(( $CREATION_COUNT + 1 ))
				CREATED_TARGETS=( ${CREATED_TARGETS[@]} "$opt_sendprefix/$ii" )
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
        getopt_cmd='/opt/local/bin/getopt'
        ;;
    (*)
        print_log error "Local system not known ($PLATFORM_LOC) - needs one of Darwin, Linux. Exiting."
        exit 300
        ;;
esac

GETOPT=$("$getopt_cmd" \
  --longoptions=default-exclude,dry-run,skip-scrub,recursive,send-atonce \
  --longoptions=event:,keep:,label:,prefix:,sep:,create,fallback,rollback \
  --longoptions=debug,help,quiet,syslog,verbose,send-full:,send-incr:,remove-local:,destroy \
  --options=dnshe:l:k:p:rs:qgvfixcXFRb \
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
		(-k|--keep)
			if ! test "$2" -gt '0' 2>/dev/null
			then
				print_log error "The $1 parameter must be a positive integer."
				exit 229
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
						exit 230
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

if [ -f ${tmp_file_prefix%%X*}* ]; then 
    print_log error "another copy is running ..."
    exit 99
fi  
LOCKFILE=`mktemp $tmp_file_prefix`
trap "rm -f $LOCKFILE; exit $?" INT TERM EXIT

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
  -o name,com.sun:auto-snapshot,com.sun:auto-snapshot:"$opt_label",mountpoint,canmount,snapdir) \
  || { print_log error "zfs list $?: $ZFS_LIST"; exit 136; }
  
ZFS_LOCAL_LIST=($(echo "$ZFS_LIST" | awk -F'\t' '{ORS="\n"}{print $1}'))

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
declare -a TARGETS_DRECURSIVE=('')
declare -a TARGETS_TMP_RECURSIVE=('')

# Initialize the list of datasets that will get a non-recursive snapshot.
declare -a TARGETS_DREGULAR=('')

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

	for jj in $NOAUTO
	do
		# Ibid regarding iii.
		jjj="$jj/"
		
		# The --recursive switch only matters for non-wild arguments.
		if [ -z "$opt_recursive" -a "$1" != '//' ]
		then
			# Snapshot this dataset non-recursively.
			print_log debug "Including $ii for regular snapshot."
			TARGETS_DREGULAR=( ${TARGETS_DREGULAR[@]} $( printf "%s\n" $ii))
			continue 2
		# Check whether the candidate name is excluded
		elif [ "$jjj" = "$iii" ]
		then
			continue 2
		# Check whether the candidate name is a prefix of any excluded dataset name.
		elif [ "$jjj" != "${jjj#$iii}" ]
		then
			# Snapshot this dataset non-recursively.
			print_log debug "Including $ii for regular snapshot."
			TARGETS_DREGULAR=( ${TARGETS_DREGULAR[@]} $( printf "%s\n" $ii))
			continue 2
		fi
	done

	for jj in ${TARGETS_TMP_RECURSIVE[@]}
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
	TARGETS_TMP_RECURSIVE=( ${TARGETS_TMP_RECURSIVE[@]} $( printf "%s\n" $ii) )
	
done

# Linux lacks SMF and the notion of an FMRI event, but always set this property
# because the SUNW program does. The dash character is the default.
SNAPPROP="-o com.sun:auto-snapshot-desc='$opt_event'"

# ISO style date; fifteen characters: YYYY-MM-DD-HHMM
# On Solaris %H%M expands to 12h34.
DATE=$(date +%F-%H%M)

# The snapshot name after the @ symbol.
SNAPNAME="$opt_prefix${opt_label:+$opt_sep$opt_label-$DATE}"

# The expression for matching old snapshots.  -YYYY-MM-DD-HHMM
SNAPGLOB="$opt_prefix${opt_label:+?$opt_label}????????????????"

if test -n "$TARGETS_DREGULAR"; then
    print_log info "Doing regular snapshots of ${TARGETS_DREGULAR[@]}"
    SNAPSHOTS_OLD_LOC=( $(eval zfs list -r -d 1 -H -t snapshot -S creation -o name $(printf "%s " ${TARGETS_DREGULAR[@]}) ))
fi

if test -n "$TARGETS_TMP_RECURSIVE"; then
    print_log info "Doing recursive snapshots of ${TARGETS_TMP_RECURSIVE[@]}"
    SNAPSHOTS_OLD_LOC=( ${SNAPSHOTS_OLD_LOC[@]} $(eval zfs list -r -H -t snapshot -S creation -o name $(printf "%s " ${TARGETS_TMP_RECURSIVE[@]} ) )) \
        || { print_log error "zfs list $?: $SNAPSHOTS_OLD_LOC"; exit 137; }
fi

test -n "$opt_dry_run" \
  && print_log info "Doing a dry run. Not running these commands..."

# expand FS list if replication is not used 
if [ "$opt_recursive" = ' ' -o "$1" = "//" ]
then
    for ii in ${TARGETS_TMP_RECURSIVE[@]}; do TARGETS_DRECURSIVE=( ${TARGETS_DRECURSIVE[@]} $(printf "%s\n" ${ZFS_LOCAL_LIST[@]} | grep ^$ii) ); done
else
    TARGETS_DRECURSIVE=( ${TARGETS_TMP_RECURSIVE[@]} )
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

    MOUNTED_LIST_REM=$(eval do_getmountedfs "remote")

    SNAPSHOTS_OLD_REM=($(eval "$opt_sendtocmd" zfs list -r -H -t snapshot -S creation -o name "$opt_sendprefix")) \
                          || { print_log error "zfs list $?: $SNAPSHOTS_OLD_REM"; exit 140; }

    ZFS_REMOTE_LIST=($(eval "$opt_sendtocmd" zfs list -H -t filesystem,volume -s name -o name)) \
                         || { print_log error "$opt_sendtocmd zfs list $?: $ZFS_REMOTE_LIST"; exit 139; }
fi

if [ "$opt_create" -eq '1' -a "$opt_send" != "no" ]; then
    do_createfs "${TARGETS_DREGULAR[*]}"
    do_createfs "${TARGETS_DRECURSIVE[*]}"
fi

do_snapshots "$SNAPPROP" "" "$SNAPNAME" "$SNAPGLOB" "${TARGETS_DREGULAR[*]}"
do_snapshots "$SNAPPROP" "$opt_recursive" "$SNAPNAME" "$SNAPGLOB" "${TARGETS_DRECURSIVE[*]}"

print_log notice "@$SNAPNAME," \
  "$SNAPSHOT_COUNT created snapshots," \
  "$SENT_COUNT sent snapshots," \
  "$DESTRUCTION_COUNT destroyed," \
  "$CREATION_COUNT created filesystems," \
  "$WARNING_COUNT warnings."

exit 0
# }
