#!/bin/sh

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
KEEP=''

# Other global variables.
declare -a SNAPSHOTS_OLD_LOC
declare -a SNAPSHOTS_OLD_REM
declare -a CREATED_TARGETS
declare -a ZFS_REMOTE_LIST
declare -a ZFS_LOCAL_LIST
declare -a TARGETS_DRECURSIVE
declare -a TARGETS_DREGULAR
declare -i RC

tmp_file_prefix='zfs-auto-snapshot.XXXXXXXXX'


set -o pipefail

print_usage ()
{
	echo "Usage: $0 [options] [-l label] <'//' | name [name...]>
  --default-exclude  Exclude datasets if com.sun:auto-snapshot is unset.
  --remove-local=n   Remove local snapshots after successfully sent via --send-incr or --send-full but still keeps n snapshots.
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
      --send-full=F  Send zfs full backup. Unimplemented.
      --send-incr=F  Send zfs incremental backup. Unimplemented.
      --sep=CHAR     Use CHAR to separate date stamps in snapshot names.
  -b, --rollback     Roll back remote filesystem to match currently sending snapshot. 
  -X, --destroy      Destroy remote snapshots to allow --send-full if destination has snapshots (needed for -F in case incremental
                     snapshots on local and remote do not match).
  -F, --fallback     Allow fallback from --send-incr to --send-full, if incremental sending is not possible (filesystem on remote just
                     created or snapshots do not match - see -X).  
  -g, --syslog       Write messages into the system log.
  -r, --recursive    Snapshot named filesystem and all descendants.
  -R, --replication  Use zfs's replication (zfs send -R) instead of simple send over newly created snapshots (check man zfs for details).
  -v, --verbose      Print info messages.
  -f, --force        Passes -F argument to zfs receive
      name           Filesystem and volume names, or '//' for all ZFS datasets.
" 
}


trap "{ rm -f $LOCKFILE; }" EXIT


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


do_send ()
{
    local SENDTYPE="$1"
    local SNAPFROM="$2"
    local SNAPTO="$3"
    local SENDFLAGS="$4"
    local REMOTEFS="$5"
    
    
    test $SENDTYPE = "incr" && do_run "zfs send " "$SENDFLAGS" "$opt_atonce  $SNAPFROM   $SNAPTO" "$opt_pipe" "$opt_sendtocmd" "zfs recv  $opt_force -u $REMOTEFS"
    test $SENDTYPE = "full" && do_run "zfs send " "$SENDFLAGS" "$SNAPTO" "$opt_pipe" "$opt_sendtocmd" "zfs recv $opt_force -u $REMOTEFS"
    
    test "$RC" -ne '0' && WARNING_COUNT=$(( $WARNING_COUNT + 1 ))

    return "$RC"

}

do_delete ()
{

    local DEL_TYPE="$1"
    local SNAPNAME="$2"
    local FLAGS="$3"
    
    KEEP=$(( $KEEP - 1 ))
    if [ "$KEEP" -le '0' ]
    then
	case "$DEL_TYPE" in
	    (remote)
			do_run "$opt_sendtocmd" "zfs destroy $FLAGS '$SNAPNAME'"
			;;
	    (local)
			do_run "zfs destroy $FLAGS '$SNAPNAME'"
			;;
	esac 

	if [ "$RC" -eq 0 ]
	then
			DESTRUCTION_COUNT=$(( $DESTRUCTION_COUNT + 1 ))
	else
			WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
	fi
    
    fi
    
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

do_snapshots () # properties, flags, snapname, oldglob, [targets...]
{
	local PROPS="$1"
	local sFLAGS="$2"
	local NAME="$3"
	local GLOB="$4"
	local TARGETS=(${5})
	local KEEP=''
	
	test "$sFLAGS" = '-R' && FLAGS='-r' 

	for ii in ${TARGETS[@]}
	do

		FALLBACK='0'
		SND_RC='1'
		
		print_log debug "...Snapshooting $ii"
		
		if do_run "zfs snapshot $PROPS $FLAGS '$ii@$NAME'" 
		then
			SNAPSHOT_COUNT=$(( $SNAPSHOT_COUNT + 1 ))
		else
			WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
			continue
		fi 
		

		if [ "$opt_send" = "incr" ]
		then
		    LAST_REMOTE=$(printf "%s\n" "${SNAPSHOTS_OLD_REM[@]}" | grep "$opt_sendprefix$ii@" | grep -m1 . | awk -F'@' '{print $2}')
		
		    if [ -z "$LAST_REMOTE" ] 
		    then
			# no snapshot on remote
			FALLBACK='1'
		    else
		        # last snapshot on remote is no more available on local, this applies both for -r and non -r runs
			if [ $(printf "%s\n" "${SNAPSHOTS_OLD_REM[@]}" | grep -e ^$opt_sendprefix$ii.*@$LAST_REMOTE | grep -c . ) -ne \
			    $(printf "%s\n" "${SNAPSHOTS_OLD_LOC[@]}" | grep -e ^$ii.*@$LAST_REMOTE | grep -c . ) ]
			then
			    FALLBACK='3'
			fi
		    fi
			
		    # remote filesystem just created. if -R run, check childen as well
		    is_member "${CREATED_TARGETS[*]}" "$opt_sendprefix$ii"
		    if [ "$?" -eq 1 ]; then 
			FALLBACK='2'; 
		    elif [ -n "$sFLAGS" ]; then
			if [ test $(printf "%s\n" ${CREATED_TARGETS[@]} | grep ^"$opt_sendprefix$ii/" ) != '' ]; then FALLBACK='4'; fi
		    fi

		    case "$FALLBACK" in
		        (1)
			    print_log info "falling back to full send, no snapshot exists at destination: $ii"
			    ;;
			(2|4)
			    print_log info "falling back to full send, remote filesystem was just created: $ii"
			    ;;
			(3)
			    print_log info "falling back to full send, last snapshot on remote is not available on local: $ii"
			    ;;
			(0)
			    do_send "incr" "$ii@$LAST_REMOTE" "$ii@$NAME" "$sFLAGS" "$opt_sendprefix$ii"
			    SND_RC="$?"
			    ;;
		    esac

		    case "$FALLBACK" in 
			(3|4)
			    test "$opt_destroy" -eq '1' && do_run "$opt_sendtocmd" "zfs list -H -t snapshot -o name" "|" "grep $opt_sendprefix$ii@" "$opt_pipe" "$opt_sendtocmd" "xargs -L1 zfs destroy $FLAGS"
			    ;;
		    esac

		fi
		
		if [ "$opt_send" = "full" -o "$FALLBACK" -ne '0' -a "$opt_fallback" -eq '1' ]
		then
		    do_send "full" "" "$ii@$NAME" "$sFLAGS" "$opt_sendprefix$ii"
		    SND_RC="$?"
		fi
		

		# Retain at most $opt_keep number of old snapshots of this filesystem,
		# including the one that was just recently created.
		
		if [ -z "$opt_keep" ]
		then
		    print_log debu "Number of snapshots not specified. Keeping all."
		    continue
		elif [ "$opt_send" != "no" ] && [ "$SND_RC" -ne '0' ]
		then
		    print_log debug "Sending of filesystem was requested, but send failed. Ommiting destroy procedures."
		    continue
		elif [ "$opt_send" != "no" -a -n "$opt_remove" ]
		then
		    KEEP="$opt_remove"
		    print_log debug "Sending was successful, removal of local snapshots requested. Keeping only $KEEP."
		else
		    KEEP="$opt_keep"
		    print_log debug "Deleting local snapshots, keeping $KEEP."		    
		fi

		# ASSERT: The old snapshot list is sorted by increasing age.
		for jj in ${SNAPSHOTS_OLD_LOC[@]}
		do
			# Check whether this is an old snapshot of the filesystem.
			test -z "${jj#$ii@$GLOB}" -o -z "${jj##$ii@$opt_prefix*}" -a -n "$opt_remove" \
			    -a "$opt_send" != "no" && do_delete "local" "$jj" "$FLAGS"
		done

		if [ "$opt_send" = "no" -o "$sFLAGS" = "-R" ]
		then
		    print_log debug "No sending option or replication, skipping remote snapshot removal."
		    continue
		elif  [ "$opt_destroy" -eq '1' -a "$FALLBACK" -eq '3' ]
		then
		    print_log debug "Sent full copy, all remote snapshots were already destroyed."
		    continue
		else
		    KEEP="$opt_keep"
		    print_log debug "Deleting remote snapshots, keeping only $KEEP."
		fi

		# ASSERT: The old snapshot list is sorted by increasing age.
		for jj in ${SNAPSHOTS_OLD_REM[@]}
		do
			# Check whether this is an old snapshot of the filesystem.
			test -z "${jj#$opt_sendprefix$ii@$GLOB}" && do_delete "remote" "$jj" "$FLAGS" 
		done

	done
}

do_createfs ()
{

    local FS=(${1})
    
    for ii in ${FS[@]}; do
     
    print_log debug "checking: $opt_sendprefix$ii"

    if is_member "${ZFS_REMOTE_LIST[*]}" "$opt_sendprefix$ii" -eq 0
    then
	    print_log debug "creating: $opt_sendprefix$ii"
	    
	    if do_run "$opt_sendtocmd" "zfs create $opt_sendprefix$ii"
	    then
	        CREATION_COUNT=$(( $CREATION_COUNT + 1 ))
	        CREATED_TARGETS=( ${CREATED_TARGETS[@]} "$opt_sendprefix$ii" )
	    else 
	        WARNING_COUNT=$(( $WARNING_COUNT + 1 ))
	    fi
    fi
    done
    
}

# main ()
# {
                    
GETOPT=$('/opt/local/bin/getopt' \
  --longoptions=default-exclude,dry-run,skip-scrub,recursive,send-atonce \
  --longoptions=event:,keep:,label:,prefix:,sep:,create,fallback,rollback \
  --longoptions=debug,help,quiet,syslog,verbose,send-full:,send-incr:,remove-local:,destroy \
  --options=dnshe:l:k:p:rs:qgvfixcXFbR \
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
				exit 139
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
		(-b|--rollback)
			opt_force='-F'
			shift 1
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
		(--send-full)
			if [ -n "$opt_sendprefix" ]
			then
				print_log error "Only one of --send-incr and --send-full must be specified."
				exit 139
			fi
			opt_sendprefix="$2/"
			opt_send='full'			
			shift 2
			;;
		(--send-incr)
			opt_sendincr="$2"
			if [ -n "$opt_sendprefix" ]
			then
				print_log error "Only one of --send-incr and --send-full must be specified."
				exit 140
			fi
			opt_sendprefix="$2/"
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
				exit 141
			fi
			opt_remove="$2"
			shift 2
			;;
		(-v|--verbose)
			opt_quiet=''
			opt_verbose='1'
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

ZFS_LOCAL_LIST=($(echo "$ZFS_LIST" | awk -F'\t' '{ORS="\n"}{print $1}'))

SNAPSHOTS_OLD_LOC=($(env LC_ALL=C zfs list -H -t snapshot -S creation -o name)) \
   || { print_log error "zfs list $?: $SNAPSHOTS_OLD_LOC"; exit 137; }

if [ "$opt_send" != "no" ]
then
    SNAPSHOTS_OLD_REM=($(eval "$opt_sendtocmd" zfs list -H -t snapshot -S creation -o name | grep "$opt_sendprefix")) \
   || { print_log error "zfs list $?: $SNAPSHOTS_OLD_REM"; exit 138; }

    ZFS_REMOTE_LIST=($(eval "$opt_sendtocmd" zfs list -H -t filesystem,volume -s name -o name)) \
    || { print_log error "$opt_sendtocmd zfs list $?: $ZFS_REMOTE_LIST"; exit 139; }
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



WAITING=0
while [ -f /tmp/"$tmp_file_prefix"* ]; do
    if [ "$WAITING" -gt 12 ]; then
	print_log warning "exiting due to lock file ... "
	exit 555
    fi
    print_log warning "sleeping on lock file ... $WAITING"
    sleep 5
    let WAITING=WAITING+1
done
LOCKFILE=`mktemp -t $tmp_file_prefix`


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
  'tolower($2) !~ /false/ && tolower($3) !~ /false/ {print $1}')

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
declare -a TARGETS_DRECURSIVE
declare -a TARGETS_TMP_RECURSIVE

# Initialize the list of datasets that will get a non-recursive snapshot.
declare -a TARGETS_DREGULAR


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
	#TARGETS_DRECURSIVE=( ${TARGETS_DRECURSIVE[@]} $(printf "%s\n" ${ZFS_LOCAL_LIST[@]} | grep ^$ii) )
	
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


test -n "$TARGETS_DREGULAR" \
  && print_log info "Doing regular snapshots of ${TARGETS_DREGULAR[@]}"

test -n "$TARGETS_TMP_RECURSIVE" \
  && print_log info "Doing recursive snapshots of ${TARGETS_TMP_RECURSIVE[@]}"

test -n "$opt_dry_run" \
  && print_log info "Doing a dry run. Not running these commands..."

# expand FS list if replication is not used 
if [ "$opt_recursive" = ' ' -o "$1" = "//" ]
then
    for ii in "${TARGETS_TMP_RECURSIVE[@]}"; do TARGETS_DRECURSIVE=( ${TARGETS_DRECURSIVE[@]} $(printf "%s\n" ${ZFS_LOCAL_LIST[@]} | grep ^$ii) ); done
else
    TARGETS_DRECURSIVE=( ${TARGETS_TMP_RECURSIVE[@]} )
fi

if [ "$opt_create" -eq '1' -a "$opt_send" != "no" ]; then
    do_createfs "${TARGETS_DREGULAR[*]}"
    do_createfs "${TARGETS_DRECURSIVE[*]}"
fi

do_snapshots "$SNAPPROP" "" "$SNAPNAME" "$SNAPGLOB" "${TARGETS_DREGULAR[*]}"
do_snapshots "$SNAPPROP" "$opt_recursive" "$SNAPNAME" "$SNAPGLOB" "${TARGETS_DRECURSIVE[*]}"

print_log notice "@$SNAPNAME," \
  "$SNAPSHOT_COUNT created snapshots," \
  "$DESTRUCTION_COUNT destroyed," \
  "$CREATION_COUNT created filesystems," \
  "$WARNING_COUNT warnings."

rm -f $LOCKFILE

exit 0
# }
