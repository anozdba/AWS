#!/usr/bin/perl
# --------------------------------------------------------------------
# genBackupS3Updates.pl
#
# $Id: genBackupS3Updates.pl,v 1.1 2019/06/26 22:39:06 db2admin Exp db2admin $
#
# Description:
# Script to generate a file of dbbackup update statements updating the 
# S3 filename
#
# Usage:
#   genBackupS3Updates.pl -f fileName
#
# $Name:  $
#
# ChangeLog:
# $Log: genBackupS3Updates.pl,v $
# Revision 1.1  2019/06/26 22:39:06  db2admin
# Initial revision
#
# --------------------------------------------------------------------

use strict;

my $ID = '$Id: genBackupS3Updates.pl,v 1.1 2019/06/26 22:39:06 db2admin Exp db2admin $';
my @V = split(/ /,$ID);
my $Version=$V[2];
my $Changed="$V[3] $V[4]";

my $machine;            # machine name
my $machine_info;       # ** UNIX ONLY ** uname
my @mach_info;          # ** UNIX ONLY ** uname split by spaces
my $OS;                 # OS
my $scriptDir;          # directory where the script is running
my $tmp;
my $dirSep;             # directory separator
my $tempDir; 
my $logDir;

BEGIN {
  if ( $^O eq "MSWin32") {
    $machine = `hostname`;
    $OS = "Windows";
    $scriptDir = 'c:\udbdba\scripts';
    $logDir = 'logs\\';
    $tmp = rindex($0,'\\');
    if ($tmp > -1) {
      $scriptDir = substr($0,0,$tmp+1)  ;
    }
    $dirSep = '\\';
    $tempDir = 'c:\temp\\';
  }
  else {
    $machine = `uname -n`;
    $machine_info = `uname -a`;
    @mach_info = split(/\s+/,$machine_info);
    $OS = $mach_info[0] . " " . $mach_info[2];
    $scriptDir = "scripts";
    $tmp = rindex($0,'/');
    if ($tmp > -1) {
      $scriptDir = substr($0,0,$tmp+1)  ;
    }
    $logDir = `cd; pwd`;
    chomp $logDir;
    $logDir .= '/logs/';
    $dirSep = '/';
    $tempDir = '/var/tmp/';
  }
}
use lib "$scriptDir";

chomp $machine;

use commonFunctions qw(getOpt myDate trim $getOpt_optName $getOpt_optValue @myDate_ReturnDesc $cF_debugLevel ingestData tablespaceStateLit displayDebug getCurrentTimestamp performTimestampSubtraction);

sub usage {
  if ( $#_ > -1 ) {
    if ( trim("$_[0]") ne "" ) {
      print "\n$_[0]\n\n";
    }
  }

  print "Usage: $0 -?hs -f <Filename>] [-v[v]] [-d database] 

       Version $Version Last Changed on $Changed (UTC)

       -h or -?        : This help message
       -s              : Silent mode (in this program only suppesses parameter messages)
       -d              : Database to list
       -v              : turn on verbose/debug mode
       -f              : this is the file that holds the list of s3 files
\n";

}

my $inFile = "";
my $silent = 0;
my $debugLevel = 0;
my $database = '';
my $nl = '';

# ----------------------------------------------------
# -- Start of Parameter Section
# ----------------------------------------------------

# Initialise vars for getOpt ....

while ( getOpt(":?hsvd:f:") ) {
 if (($getOpt_optName eq "h") || ($getOpt_optName eq "?") )  {
   usage ("");
   exit;
 }
 elsif (($getOpt_optName eq "s"))  {
   $silent = 1;
 }
 elsif (($getOpt_optName eq "v"))  {
   $debugLevel++;
   $cF_debugLevel++;
   if ( ! $silent ) {
     print "Debug Level set to $debugLevel\n";
   }
 }
 elsif (($getOpt_optName eq "d"))  {
   $database = $getOpt_optValue;
   if ( ! $silent ) {
     print "A connect to database $database will be generated in the output\n";
   }
 }
 elsif (($getOpt_optName eq "f"))  {
   $inFile = $getOpt_optValue;
   if ( ! $silent ) {
     print "File '$inFile' will be used to read in the s3 file names\n";
   }
 }
 elsif ( $getOpt_optName eq ":" ) {
   usage ("Parameter $getOpt_optValue requires a parameter");
   exit;
 }
 else { # handle other entered values ....
   if ( $inFile eq "" ) {
     $inFile = $getOpt_optValue;
     if ( ! $silent ) {
       print "File $inFile will be used to read the db2pd -hadr output from\n";
     }
   }
   else {
     usage ("Parameter $getOpt_optValue : This parameter is unknown");
     exit;
   }
 }
}

# ----------------------------------------------------
# -- End of Parameter Section
# ----------------------------------------------------

my @ShortDay = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat');
my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
my $year = 1900 + $yearOffset;
my $month = $month + 1;
$hour = substr("0" . $hour, length($hour)-1,2);
my $minute = substr("0" . $minute, length($minute)-1,2);
my $second = substr("0" . $second, length($second)-1,2);
my $month = substr("0" . $month, length($month)-1,2);
my $day = substr("0" . $dayOfMonth, length($dayOfMonth)-1,2);
my $NowTS = "$year.$month.$day $hour:$minute:$second";
my $NowDayName = "$year/$month/$day ($ShortDay[$dayOfWeek])";
my $date = "$year.$month.$day";

my $LTSPIPE;
if ( uc($inFile) eq 'STDIN' ) { 
  open ($LTSPIPE,"-") || die "Unable to open $inFile\n"; 
  if ( ! $silent ) { print "Input will be read from STDIN\n"; }
}
else {
  if ( trim($inFile) eq '' ) {
    print "Input filename must be provided\n";
    exit 8;
  }
  else {
    open ($LTSPIPE,"<",$inFile) || die "Unable to open $inFile\n"; 
    if ( ! $silent ) { print "Input will be read from '$inFile'\n"; }
  }
}

my $currentSection = '';

# data to be collected ....

# spaceData/S3FileSync_ADBDB2TST_1month_files.txt:2019-05-27 09:00:52  198299648 1month/ADBDB2TST/backups/stm3tst/STM3TST.0.STMIN3T.DBPART000.20190527090008.001
# spaceData/S3FileSync_ADBDB2TST_1month_files.txt:2019-05-28 09:00:51  198299648 1month/ADBDB2TST/backups/stm3tst/STM3TST.0.STMIN3T.DBPART000.20190528090008.001
# spaceData/S3FileSync_ADBDB2TST_1month_files.txt:2019-05-29 09:00:48  198299648 1month/ADBDB2TST/backups/stm3tst/STM3TST.0.STMIN3T.DBPART000.20190529090009.001
# spaceData/S3FileSync_ADBDB2TST_1month_files.txt:2019-05-30 09:00:48  198299648 1month/ADBDB2TST/backups/stm3tst/STM3TST.0.STMIN3T.DBPART000.20190530090009.001
# spaceData/S3FileSync_ADBDB2TST_1month_files.txt:2019-05-31 09:00:53  198299648 1month/ADBDB2TST/backups/stm3tst/STM3TST.0.STMIN3T.DBPART000.20190531090009.001

my $inputFile = '';
my $recDate = '';
my $recTime = '';
my $recSize = '';
my $s3file = '';
my $recMachine = '';
my $recInstance = '';
my $recDatabase = '';
my $recBackupKey = '';
my $recSeq = '';
my $recBackupTS = '';
my $s3Bucket = '';
my %deleteArray = ();

my %monthNumber = ( 'Jan' =>  '01', 'Feb' =>  '02', 'Mar' =>  '03', 'Apr' =>  '04', 'May' =>  '05', 'Jun' =>  '06',
                    'Jul' =>  '07', 'Aug' =>  '08', 'Sep' =>  '09', 'Oct' =>  '10', 'Nov' =>  '11', 'Dec' =>  '12',
                    'January' =>  '01', 'February' =>  '02', 'March' =>  '03', 'April' =>  '04', 'May' =>  '05', 'June' =>  '06',
                    'July' =>  '07', 'August' =>  '08', 'September' =>  '09', 'October' =>  '10', 'November' =>  '11', 'December' =>  '12' );
 
while (<$LTSPIPE>) {

  chomp $_;

  if ( trim($_) eq '' ) { next; } # ignore blank lines

  if ( $debugLevel > 0 ) { print "Input: $_\n"; }

  if ( $_ =~ /S3 Bucket:/ ) { 
    ($s3Bucket) = ( $_ =~ /S3 Bucket: (.*)$/ ) ;
    next ; 
  }

  ( $inputFile, $recDate, $recTime, $recSize, $s3file ) = ( $_ =~ /(\S*)\:(\S*) (\S*) *(\d*) (\S*)/ );
  if ( $debugLevel > 0 ) { print "inputFile: $inputFile, recDate: $recDate, recTime: $recTime, recSize: $recSize, s3file, $s3file\n"; }

  ( $recMachine, $recDatabase, $recInstance, $recBackupTS, $recSeq ) = ( $s3file =~ /\/([^\/]*)\/.*\/([^\.]*)\..\.([^\.]*)\..*DBPART....([^\.]*)\.(.*)$/ );
  if ( $debugLevel > 0 ) { print "recMachine: $recMachine, recDatabase: $recDatabase, recInstance: $recInstance, recBackupTS: $recBackupTS, recSEQ: $recSeq\n"; }
  $recBackupKey = $recBackupTS . $recSeq;
  $recDatabase = uc($recDatabase);
  $recInstance = lc($recInstance);
  $recMachine = lc($recMachine);

  print "UPDATE dba.dbbackups set s3file = '$s3Bucket/$s3file' where database = '$recDatabase' and instance = '$recInstance' and machine = '$recMachine' and backup_time_seq = '$recBackupKey' and (s3file is null or s3file <> '$s3Bucket/$s3file')\n";

  if ( ! defined($deleteArray{"$recMachine|$recInstance|$recDatabase"}) ) { 
    $deleteArray{"$recMachine|$recInstance|$recDatabase"} = "'$recBackupKey'";
  }
  else {
    $deleteArray{"$recMachine|$recInstance|$recDatabase"} .= ",'$recBackupKey'";
  }

}
foreach my $dbKey (keys %deleteArray ) {

  my ($tmpMachine, $tmpInstance, $tmpDatabase) = split(/\|/, $dbKey);

  if ( $debugLevel > 0 ) { print "Key $tmpMachine, $tmpInstance, $tmpDatabase = (" . $deleteArray{$dbKey} . ")\n";}

  print "UPDATE dba.dbbackups set s3file = '' where database = '$tmpDatabase' and instance = '$tmpInstance' and machine = '$tmpMachine' and (s3file is not null and s3file <> '') and backup_time_seq not in (" . $deleteArray{$dbKey} . ")\n";
}

