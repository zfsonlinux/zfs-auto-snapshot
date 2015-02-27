#! /usr/bin/perl -w

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# zfs-auto-snapshot.pl : Rotate zfs snapshots 
#
# Author : Christophe Marteau
# Last modification : 27/08/2013
my $version = "1.0";
#
# Realease notes :
# 27/08/2013 : - Initial version
# 11/09/2013 : - Improve logging messages

use strict;
use Getopt::Std;
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;
use POSIX;
use DateTime;
use Hash::Merge qw/ merge /;
use Data::Dumper;
use Sys::Hostname;

my %hOptions = ();

$hOptions{'version'}{'value'}   = 0;
$hOptions{'version'}{'options'} = '.*';

$hOptions{'help'}{'value'}   = 0;
$hOptions{'help'}{'options'} = '.*';

$hOptions{'debug'}{'value'}   = 0;
$hOptions{'debug'}{'options'} = '[0-9]+';

$hOptions{'zfs-binary-path'}{'value'}   = '/sbin/zfs';
$hOptions{'zfs-binary-path'}{'options'} = '\/([-a-zA-Z0-9]+\/)+[-a-zA-Z0-9]+';

$hOptions{'zfs-volume-path'}{'value'}   = '';
$hOptions{'zfs-volume-path'}{'options'} = '([-a-zA-Z0-9]+\/)+[-a-zA-Z0-9]+';

$hOptions{'zfs-snapshot-prefix'}{'value'}   = 'GMT';
$hOptions{'zfs-snapshot-prefix'}{'options'} = '[-a-zA-Z0-9]+';

$hOptions{'zfs-snapshot-yearly'}{'value'}   = '0';
$hOptions{'zfs-snapshot-yearly'}{'options'} = '[0-9]+';

$hOptions{'zfs-snapshot-monthly'}{'value'}   = '0';
$hOptions{'zfs-snapshot-monthly'}{'options'} = '[0-9]+';

$hOptions{'zfs-snapshot-weekly'}{'value'}   = '0';
$hOptions{'zfs-snapshot-weekly'}{'options'} = '[0-9]+';

$hOptions{'zfs-snapshot-daily'}{'value'}   = '0';
$hOptions{'zfs-snapshot-daily'}{'options'} = '[0-9]+';

$hOptions{'zfs-snapshot-hourly'}{'value'}   = '0';
$hOptions{'zfs-snapshot-hourly'}{'options'} = '[0-9]+';

# function printMsg print message with level priority
# [in] $printFunctionName : The function name in which the printMsg function is call
# [in] $printPriority : The level of the message (err, crit, info, warn, debug, ...)
# [in] $printDebugLevel : The debug level for the debug priority
# [in] @aPrintString : String array to display
my $debugCurrentDecalage = 0;

sub printMsg (){
    my ($printFunctionName,$printPriority,$printDebugLevel,@aPrintMsg) = @_;

    if (($printDebugLevel == 9) && (join('',@aPrintMsg) =~ /^END /)) {
        $debugCurrentDecalage --;
    }

    my $space='';
    if ($printPriority eq "debug") {
      $space='>';
      for (my $i=0; $i < $debugCurrentDecalage; $i++) {
        $space = '=='.$space;
      }
    }

    if (($printPriority ne "debug") or ($hOptions{'debug'}{'value'} >= $printDebugLevel)) {
        my @aPrintMsgDisplayed = split("\n",join('',@aPrintMsg));
        my $timeStamp =  DateTime->now();
        for (my $i=0; $i<scalar(@aPrintMsgDisplayed); $i++) {
            print($timeStamp->strftime('%b %d %T').' '.hostname.' '.$0.': ['.$printPriority.'] ('.$printFunctionName.') '.
                  $space.$aPrintMsgDisplayed[$i]."\n");
        }
    }

    if (($printDebugLevel == 9) && (join('',@aPrintMsg) =~ /^BEGIN /)) {
        $debugCurrentDecalage ++;
    }
}

# Error function which print message and exit
# [in] $functionName : The function name in which the error function is call
# [in] @a_String : String array to display
sub error (){
  my ( $functionName, @a_String) = @_;
 
  my $space='>';
  for (my $i=0; $i < $debugCurrentDecalage; $i++) {
    $space = '=='.$space;
  }
 
  my @a_StringDisplayed = split("\n",join('',@a_String));
 
  for (my $i=0; $i<scalar(@a_StringDisplayed); $i++) {
    print STDERR '# ERROR ('.$functionName.') : '.'{'.$a_StringDisplayed[$i].'} '."\n" ;
  }
  exit(0);
}

# Fonction qui teste les options passées en parametres du
# programme et génère une aide si l'option n'est pas valide
sub parseOptions {
    &printMsg('parseOptions','debug',9,'BEGIN parseOptions');
    
    if ($hOptions{'help'}{value}) {
	pod2usage(-message => 'Displaying help ...'."\n",-exitval => 1);
    }
    
    if ($hOptions{'version'}{'value'}) {
	print($0.' v'.$version."\n");
	exit(0);
    }
    
    foreach my $option (sort (keys (%hOptions))) {
	&printMsg('parseOptions','debug',9,'Parsing option "'.
	       $option.'" = {'.$hOptions{$option}{'value'}.'} with /^'.
	       $hOptions{$option}{'options'}.'$/');
	if (exists($hOptions{$option}{'options'})) {
	    if ($hOptions{$option}{'value'} !~
		/^$hOptions{$option}{'options'}$/) {
		pod2usage(-message => 'Valeur "'.$hOptions{$option}{'value'}.'" pour l\'option "'.$option.'" incorrecte.'."\n",
			  -exitval => 1);
	    }
	}
	&printMsg('parseOptions','debug',5,'Option "'.$option.'" = {'.
	       $hOptions{$option}{'value'}.'}');
    }
    &printMsg('parseOptions','debug',9,'END parseOptions');
}

sub generateTimeStamp() {
  &printMsg('generateTimeStamp','debug',9,'BEGIN generateTimeStamp');
  my ($zfsSnapshotPrefix,$timeStamp,$timeStampType,$timeStampKeeped) = @_;
  &printMsg('generateTimeStamp','debug',5,'generateTimeStamp('.$zfsSnapshotPrefix.','.$timeStamp.','.$timeStampType.','.$timeStampKeeped.')');
  my %hGenerateTimeStamp=();
  my $dateTime = $timeStamp->clone();
  $dateTime->truncate( to => $timeStampType );
  for(my $keepedCount=0; $keepedCount < $timeStampKeeped ; $keepedCount++) {
    &printMsg('generateKeepedTimeStamp','debug',8,'Keeped '.$timeStampType.' timestamp : ['.$dateTime->datetime().']');
    &printMsg('generateKeepedTimeStamp','debug',8,'Generated '.$timeStampType.' snapshot timestamp pattern to keep : ['.$zfsSnapshotPrefix.'-'.$dateTime->strftime('%Y.%m.%d-%H.').']');
    $hGenerateTimeStamp{$zfsSnapshotPrefix.'-'.$dateTime->strftime('%Y.%m.%d-%H.')}="$timeStampType";
    $dateTime->subtract( $timeStampType.'s' => 1 );
  }
  &printMsg('generateTimeStamp','debug',5,'generateTimeStamp('.$zfsSnapshotPrefix.','.$timeStamp.','.$timeStampType.','.$timeStampKeeped.')='.Dumper(\%hGenerateTimeStamp));
  return(\%hGenerateTimeStamp);
  &printMsg('generateTimeStamp','debug',9,'END generateTimeStamp');
}

sub generateKeepedTimeStamp() {
  &printMsg('generateKeepedTimeStamp','debug',9,'BEGIN generateKeepedTimeStamp');
  my ($zfsSnapshotPrefix,$timeStamp,%timeStampMap) = @_;
  &printMsg('generateKeepedTimeStamp','debug',5,'generateKeepedTimeStamp('.$zfsSnapshotPrefix.','.$timeStamp.','.Dumper(\%timeStampMap).')');
  my %hGenerateKeepedTimeStamp=();
  &printMsg('generateKeepedTimeStamp','debug',8,'Script timestamp : ['.$timeStamp->datetime().']');

  foreach my $timeStampType (sort {$timeStampMap{$a}{'id'} <=> $timeStampMap{$b}{'id'}} (keys(%timeStampMap))) {
    &printMsg('generateKeepedTimeStamp','debug',5,'hash='.Dumper(&generateTimeStamp($zfsSnapshotPrefix,$timeStamp,$timeStampType,$timeStampMap{$timeStampType}{'value'})));
    %hGenerateKeepedTimeStamp = %{merge(\%hGenerateKeepedTimeStamp,&generateTimeStamp($zfsSnapshotPrefix,$timeStamp,$timeStampType,$timeStampMap{$timeStampType}{'value'}))};
  }
  &printMsg('generateKeepedTimeStamp','debug',5,'generateKeepedTimeStamp('.$zfsSnapshotPrefix.','.$timeStamp.','.Dumper(\%timeStampMap).')='.Dumper(\%hGenerateKeepedTimeStamp));
  return(\%hGenerateKeepedTimeStamp);
  &printMsg('generateKeepedTimeStamp','debug',9,'END generateKeepedTimeStamp');
}

sub createZfsSnapshots {
    &printMsg('createZfsSnapshots','debug',9,'BEGIN createZfsSnapshots');
    my ($zfsVolumePath,$zfsSnapshotPrefix,$timeStamp) = @_;
    &printMsg('createZfsSnapshots','debug',5,'createZfsSnapshots('.$zfsVolumePath.','.$zfsSnapshotPrefix.','.$timeStamp.')');
    my $zfsVolumeListCmd = $hOptions{'zfs-binary-path'}{'value'}.' list -Hr '.$zfsVolumePath.' 2>&1';
    &printMsg('createZfsSnapshots','debug',8,'Executing command "'.$zfsVolumeListCmd.'" ...');
    if (open(my $fhZfsVolumeList,'-|',$zfsVolumeListCmd)) {
      while(my $line = <$fhZfsVolumeList>) {
        chomp($line);
        &printMsg('createZfsSnapshots','debug',8,'Volume line "'.$line.'" for root volume "'.$zfsVolumePath.'" : [FOUND]');
        if ("$line" =~ /^(\S+)\s+\S+\s+\S+\s+\S+\s+\S+$/) {
          my $volumeName="$1";
          &printMsg('createZfsSnapshots','debug',8,'Volume "'.$volumeName.'" for root volume "'.$zfsVolumePath.'" : [FOUND]');
          my $zfsSnapshotCreateCmd = $hOptions{'zfs-binary-path'}{'value'}.' snapshot '.$volumeName.'@'.$zfsSnapshotPrefix.'-'.$timeStamp->strftime('%Y.%m.%d-%H.%M.%S').' 2>&1' ;
          &printMsg('createZfsSnapshots','debug',8,'Executing command "'.$zfsSnapshotCreateCmd.'" ...');
          if (open(my $fhZfsSnapshotCreate,'-|',$zfsSnapshotCreateCmd)) {
            my $line = <$fhZfsSnapshotCreate>;
            if (not(defined($line))) {
              &printMsg('createZfsSnapshots','info',0,'Snapshot "'.$volumeName.'@'.$zfsSnapshotPrefix.'-'.$timeStamp->strftime('%Y.%m.%d-%H.%M.%S').'" for volume "'.$volumeName.'" in root volume "'.$zfsVolumePath.'" : [CREATED]');
            } else {
              chomp($line);
              &error('createZfsSnapshots','Unable to create zfs snapshot "'.$volumeName.'" ('.$line.').');
            }
          } else {
              &error('createZfsSnapshots','Unable to execute commande "'.$zfsSnapshotCreateCmd.'".');
          }
        } else {
          &error('createZfsSnapshots','Unable to parse zfs volume line "'.$line.' for root volume "'.$zfsVolumePath.'".');
        }
      }
      close($fhZfsVolumeList);
    } else {
      &error('createZfsSnapshots','Unable to execute commande "'.$zfsVolumeListCmd.'".');
    }

    &printMsg('createZfsSnapshots','debug',9,'END createZfsSnapshots');
}

sub deleteZfsSnapshots {
    &printMsg('deleteZfsSnapshots','debug',9,'BEGIN deleteZfsSnapshots');
    my ($zfsVolumePath,$zfsSnapshotPrefix,%hGenerateKeepedTimeStamp) = @_;
    &printMsg('deleteZfsSnapshots','debug',5,'deleteZfsSnapshots('.$zfsVolumePath.','.$zfsSnapshotPrefix.','.Dumper(\%hGenerateKeepedTimeStamp).')');
    my %hSnapshot = ();
    my $zfsSnapshotListCmd = $hOptions{'zfs-binary-path'}{'value'}.' list -Hr -t snapshot '.$zfsVolumePath.' 2>&1';
    &printMsg('deleteZfsSnapshots','debug',8,'Executing command "'.$zfsSnapshotListCmd.'" ...');
    if (open(my $fhZfsSnapshotList,'-|',$zfsSnapshotListCmd)) {
      while(my $line = <$fhZfsSnapshotList>) {
        chomp($line);
        &printMsg('deleteZfsSnapshots','debug',8,'Snapshot line "'.$line.'" for root volume "'.$zfsVolumePath.'" : [FOUND]');
        if ("$line" =~ /^([^@]+\@(($zfsSnapshotPrefix-\d{4}\.\d{2}\.\d{2}-\d{2}\.)\d{2}\.\d{2}))\s+\S+\s+\S+\s+\S+\s+\S+$/) {
          my $snapshotName="$1";
          my $snapshotTimeStamp="$2";
          my $snapshotTimeStampPattern="$3";
          &printMsg('deleteZfsSnapshots','debug',8,'Snapshot "'.$snapshotName.'" with timestamp pattern "'.$snapshotTimeStampPattern.'" for root volume "'.$zfsVolumePath.'" : [FOUND]');
          if (exists($hGenerateKeepedTimeStamp{$snapshotTimeStampPattern})) {
            &printMsg('deleteZfsSnapshots','debug',8,'Snapshot "'.$snapshotName.'" with timestamp pattern "'.$snapshotTimeStampPattern.'" for root volume "'.$zfsVolumePath.'" : [KEEPED]');
 
          } else {
            my $zfsSnapshotDestroyCmd = $hOptions{'zfs-binary-path'}{'value'}.' destroy '.$snapshotName.' 2>&1' ;
            &printMsg('deleteZfsSnapshots','debug',8,'Executing command "'.$zfsSnapshotDestroyCmd.'" ...');
            if (open(my $fhZfsSnapshotDestroy,'-|',$zfsSnapshotDestroyCmd)) {
              my $line = <$fhZfsSnapshotDestroy>;
              if (not(defined($line))) {
                &printMsg('deleteZfsSnapshots','info',0,'Snapshot "'.$snapshotName.'" with timestamp pattern "'.$snapshotTimeStampPattern.'" for root volume "'.$zfsVolumePath.'" : [DELETED]');

              } else {
                chomp($line);
                &error('deleteZfsSnapshots','Unable to destroy zfs snapshot "'.$snapshotName.'" ('.$line.').');
              }
            } else {
              &error('deleteZfsSnapshots','Unable to execute commande "'.$zfsSnapshotDestroyCmd.'".');
            }
          }
        } else {
          &error('deleteZfsSnapshots','Unable to parse zfs snapshot line "'.$line.' for root volume "'.$zfsVolumePath.'".');
        }
      }
      close($fhZfsSnapshotList);
    } else {
      &error('deleteZfsSnapshots','Unable to execute commande "'.$zfsSnapshotListCmd.'".');
    }

    &printMsg('deleteZfsSnapshots','debug',9,'END deleteZfsSnapshots');
}


my $optionNumber=scalar(@ARGV);
my $options = GetOptions(
    "V|version!"                  => \$hOptions{'version'}{'value'},
    "h|help!"                     => \$hOptions{'help'}{'value'},
    "d|v|debug|verbose:1"         => \$hOptions{'debug'}{'value'},
    "p|zfs-volume-path=s"         => \$hOptions{'zfs-volume-path'}{'value'},
    "s|zfs-snapshot-prefix=s"     => \$hOptions{'zfs-snapshot-prefix'}{'value'},
    "Y|zfs-snapshot-yearly=i"     => \$hOptions{'zfs-snapshot-yearly'}{'value'},
    "M|zfs-snapshot-monthly=i"    => \$hOptions{'zfs-snapshot-monthly'}{'value'},
    "W|zfs-snapshot-weekly=i"     => \$hOptions{'zfs-snapshot-weekly'}{'value'},
    "D|zfs-snapshot-daily=i"      => \$hOptions{'zfs-snapshot-daily'}{'value'},
    "H|zfs-snapshot-hourly=i"      => \$hOptions{'zfs-snapshot-hourly'}{'value'},
    );

if (($options) && ($optionNumber > 0)){
    &parseOptions();
} else {
    pod2usage( -verbose => 2,-exitval => 1);
}

# Main program
&printMsg('main','debug',9,'BEGIN main');
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse = 1;

my $scriptTimeStamp =  DateTime->now(time_zone => "GMT");
my %timeStampMap = ( 'year'  => { 'id' => 1, 'value' => $hOptions{'zfs-snapshot-yearly'}{'value'}},
                     'month' => { 'id' => 2, 'value' => $hOptions{'zfs-snapshot-monthly'}{'value'}},
                     'week'  => { 'id' => 3, 'value' => $hOptions{'zfs-snapshot-weekly'}{'value'}},
                     'day'   => { 'id' => 4, 'value' => $hOptions{'zfs-snapshot-daily'}{'value'}},
                     'hour'  => { 'id' => 5, 'value' => $hOptions{'zfs-snapshot-hourly'}{'value'}}
                   );

&createZfsSnapshots($hOptions{'zfs-volume-path'}{'value'},$hOptions{'zfs-snapshot-prefix'}{'value'},$scriptTimeStamp);
my %hgenerateKeepedTimeStamp=();
%hgenerateKeepedTimeStamp=%{merge(\%hgenerateKeepedTimeStamp,&generateKeepedTimeStamp($hOptions{'zfs-snapshot-prefix'}{'value'},$scriptTimeStamp,%timeStampMap))};
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Terse = 1;
#print join("\n",sort(keys(%hgenerateKeepedTimeStamp)))."\n";
&deleteZfsSnapshots($hOptions{'zfs-volume-path'}{'value'},$hOptions{'zfs-snapshot-prefix'}{'value'},%hgenerateKeepedTimeStamp);
&printMsg('main','debug',9,'END main');

__END__

=head1 NAME

  zfs-auto-snapshot.pl - Take ZFS snapshots and removes old ones

=cut

=head1 DESCRIPTION

  Take ZFS snapshots and removes old ones.

=cut

=head1 SYNOPSIS

  zfs-auto-snapshot.pl [--version] [--help] [--verbose <level>] [--debug <level>] 
                       [--zfs-binary-path </path/to/zfs>]  
                        --zfs-volume-path <tank/volume> 
                        --zfs-snapshot-prefix <snapshot prefix>
                        --zfs-snapshot-yearly <number>
                        --zfs-snapshot-monthly <number>
                        --zfs-snapshot-weekly <number>
                        --zfs-snapshot-daily <number>
                        --zfs-snapshot-hourly <number>
  
  Options:
   --version                : Display plugins version.
   --help                   : Display this help.
   --verbose <level>        : Same as debug option (0-9).
   --debug <level>          : Increase debug (0-9).

   --zfs-binary-path </path/to/zfs>        : zfs binary location (Default to "/sbin/zfs")
   --zfs-volume-path <tank/volume>         : zfs volume path where you want to take snapshots
   --zfs-snapshot-prefix <snapshot prefix> : zfs snapshot prefix
   --zfs-snapshot-yearly <number>          : number of yearly zfs snapshot to keep
   --zfs-snapshot-monthly <number>         : number of monthly zfs snapshot to keep
   --zfs-snapshot-weekly <number>          : number of weekly zfs snapshot to keep
   --zfs-snapshot-daily <number>           : number of daily zfs snapshot to keep
   --zfs-snapshot-hourly <number>          : number of hourly zfs snapshot to keep

=cut

=head1 OPTIONS

=over 5

=item B<--version>

Display script version.

=item B<--help>

Display this help.

=item B<--verbose <0-9>>

Same as debug option.

=item B<--debug <0-9>>

Define a debug level between 0 and 9.
 0 means no debug and 9 means full debug (default to 0).

=item B<--zfs-volume-path <tank/volume>>

zfs volume path where you want to take snapshots

=item B<--zfs-binary-path </path/to/zfs>>

zfs binary location (Default to "/sbin/zfs")

=item B<--zfs-snapshot-prefix <snapshot prefix>>

zfs snapshot prefix

=item B<--zfs-snapshot-yearly <number>>

Number of yearly zfs snapshot to keep

=item B<--zfs-snapshot-monthly <number>>

Number of monthly zfs snapshot to keep

=item B<--zfs-snapshot-weekly <number>>

Number of weekly zfs snapshot to keep

=item B<--zfs-snapshot-daily <number>>

Number of daily zfs snapshot to keep

=item B<--zfs-snapshot-hourly <number>>

Number of hourly zfs snapshot to keep

=back

=cut

=head1 EXAMPLES

Using zfs-auto-snapshot.pl script:
   # perl zfs-auto-snapshot.pl --zfs-volume-path zfstank/home --zfs-snapshot-prefix GMT --zfs-snapshot-yearly 0 --zfs-snapshot-monthly 0 --zfs-snapshot-weekly 2 --zfs-snapshot-daily 3 --zfs-snapshot-hourly 4

You have to schedule it by cron in cron.hourly if you want to automate it
  

=cut
