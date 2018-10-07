#!/usr/bin/perl
# --------------------------------------------------------------------
# checkS3.pl
#
# $Id: checkS3.pl,v 1.5 2018/10/03 01:00:31 db2admin Exp db2admin $
#
# Description:
# Script to check AWS S3 for the existance of a backup for a specified file
#
# NOTE: It assumes that file existed on the current machine
#
# Usage:
#   checkS3.pl -f <filename>
#
#   for Unix:
#       /usr/local/bin/find /export/home/db2admin -name "*.tx*" -mmin +2400 -print |  checkS3.pl -n 2
#
#   for Windows:
#       dir /A:-D /S /B b:\ | checkS3_new.pl -N 3 -sEe -x
#
# $Name:  $
#
# ChangeLog:
# $Log: checkS3.pl,v $
# Revision 1.5  2018/10/03 01:00:31  db2admin
# dont write any messages to STDERR
#
# Revision 1.4  2018/10/02 21:36:57  db2admin
# only allow files to be deleted if they have the same file size on disk and on S3
#
# Revision 1.3  2018/10/02 06:35:49  db2admin
# correct placement of def
#
# --------------------------------------------------------------------

use strict;

my $ID = '$Id: checkS3.pl,v 1.5 2018/10/03 01:00:31 db2admin Exp db2admin $';
my @V = split(/ /,$ID);
my $Version=$V[2];
my $Changed="$V[3] $V[4]";

my $machine;   # machine we are running on
my $OS;        # OS running on
my $scriptDir; # directory the script ois running out of
my $tmp ;
my $machine_info;
my @mach_info;
my $user = 'Unknown';
my $dirsep;

BEGIN {
  if ( $^O eq "MSWin32") {
    $machine = `hostname`;
    $OS = "Windows";
    $scriptDir = 'c:\udbdba\scrxipts';
    $tmp = rindex($0,'\\');
    $user = $ENV{'USERNAME'};
    if ($tmp > -1) {
      $scriptDir = substr($0,0,$tmp+1)  ;
    }
    $dirsep = '\\';
    $user = $ENV{USERNAME};
  }
  else {
    $machine = `uname -n`;
    $machine_info = `uname -a`;
    @mach_info = split(/\s+/,$machine_info);
    $OS = $mach_info[0] . " " . $mach_info[2];
    $scriptDir = "scripts";
    $user = `id | cut -d '(' -f 2 | cut -d ')' -f 1`;
    $tmp = rindex($0,'/');
    if ($tmp > -1) {
      $scriptDir = substr($0,0,$tmp+1)  ;
    }
    $dirsep = '/';
    $user = getpwuid($<);
  }
}

use lib "$scriptDir";
use commonFunctions qw(getOpt myDate trim $getOpt_optName $getOpt_optValue @myDate_ReturnDesc $myDate_debugLevel);

# varibles
my $silent = "No";
my $debugLevel = 0;
my $inFile = 'STDIN';
my $generateDelete = 0;
my $numBackups = 2;
my $printFilename = 1;
my $client = '';
my $PI = '';
my $doDelete = 0;
my $checkUncompressed = 0;
my $S3Bucket = 'DEFAULT_BUCKET';
my $S3BucketType = '1month';
my $numDays = 2;
my $compDate = '';
my $todayNum;
my $displayDelete = 0;
my $fileAge = 0;

# Subroutines and functions ......

sub getDayNum {
  # get the day number 
  my $inDate = shift;
	
  my($sec, $min, $hour, $day, $mon, $year, $wday, $yday, $isdst) = localtime $inDate;
  my $day = substr("0" . $day, length($day)-1,2);
  my $mon = $mon + 1;
  my $mon = substr("0" . $mon, length($mon)-1,2);
  if ( $year < 65) {
    $year = "65";
    $mon = "01";
    $day = "01";
  }
  my $yyyy_mm_dd = (1900 + $year) . '-' . $mon . '-' . $day;
  my $yyyymmdd = (1900 + $year) . $mon . $day;
  my @return = myDate("DATE\:$yyyymmdd");
  return ($yyyy_mm_dd, $return[5], $return[12]);
}

sub getFileAge {
  # generate the file's age
  
  my $fileName = shift;
  
  my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat($fileName);
	
  my @comparison = ();

  if ( $compDate eq "Referenced") { 
    @comparison = getDayNum($atime);
  }
  elsif ( $compDate eq "Modified") {
    @comparison = getDayNum($mtime);
  }
  else {
    @comparison = getDayNum($ctime);
  }
	
  if ( $comparison[2] ne '' ) { # date was invalid
    print "Invalid comparison date\n"  ;
	return -1; # skip this file ...
  }
  
  my $fileage = $todayNum - $comparison[1];
  if ( $debugLevel > 0 ) { print "Comparison dates for file: $comparison[0] -  $comparison[1] - $fileage days old\n"; }

  return ($fileage,$comparison[0],$size);
}

sub processActions {
  # process a delete on the supplied file name
  my $fileName = shift;

  if ( $doDelete ) { # actually do the delete
    if ( $OS eq 'Windows' ) {
      my $tmpA = `del $fileName`;
      my $retMessage = $!;
	  # print "tmpA=$tmpA, retMessage=$retMessage\n";
      if ( ($silent ne "Yes") || ($displayDelete) ) {
        if ( $retMessage eq '' ) {
          print "File '$fileName' has been deleted - $fileAge days old\n";
        }
        else {
          print "File '$fileName' has not been deleted - $fileAge days old - $retMessage\n";
        }
      }
    }
	else { # not windows
      my $numFilesDeleted = unlink $fileName;
      my $retMessage = $!;
      if ( ($silent ne "Yes") || ($displayDelete) ) {
        if ( $numFilesDeleted > 0 ) {
          print "File '$fileName' has been deleted - $fileAge days old\n";
        }
        else {
          print "File '$fileName' has not been deleted - $fileAge days old - $retMessage\n";
        }
      }	
	}
  }
  
  # write out the delete if requested to do so
  if ( $generateDelete ) { # print out the delete
    if ( $OS eq 'Windows' ) {
      print "del '$fileName'\n";
    }
	else {
      print "rm '$fileName'\n";
	}
  }
  
  # print the filename if requested to do so
  if ( $printFilename ) { print "$fileName\n"; }
  
}	  
  

sub by_key {
  $a cmp $b ;
}

sub usage {
  if ( $#_ > -1 ) {
    if ( trim("$_[0]") ne "" ) {
      print "\n$_[0]\n\n";
    }
  }

  print "Usage: $0 -?hs [-f <file>] [-d] [-n <number of backups>] [-N <number of days>] [-v[v]] [-x] [-e] [-c <client>] [-A] [-E] [-z] [-b <bucket>] [-t <type>] [-M | -A | -C]
                   
       Script to check the existance of a AWS S3 backup of a file

       Version $Version Last Changed on $Changed (UTC)

       h or -?        : This help message
       -s              : Silent mode [if -d specified then only delete commands will be generated to STDOUT]
       -f              : file to check for (may include a directory)
                         [if not supplied then assumes file name will be supplied via STDIN]
       -d              : output a delete command to STDOUT
       -n              : number of backups to check for (a delete will only be generated if at least this many backups are found)
	                     NOTE: Only kept for compatability with checkNetbackup.pl - this script only checks for the existence of 1 backup
       -N              : number of days before eligible for removal [default: 2]
       -x              : dont print out the eligible file name
       -c              : client to use on the bplist if different to the machine running the script
       -b              : AWS S3 bucket name [default: mspdev-db2-backup]
       -t              : AWS S3 bucket type [default: 1month] - normally a sub folder aligned to a specific lifecycle policy
       -A              : do a path independent search (look for the filename in all paths)
       -E              : execute the delete
       -e              : display the delete message even if silent
       -z              : check for noncompressed backups (i.e. when checking remove the .Z at the end of the file name)
       -A              : use last accessed date as the comparison date {default)
       -M              : use last modified date as the comparison date 
       -C              : use created date as the comparison date 
       -v              : debug level
	   
	   NOTES : -A, -M and -C are mutually exclusive

\n";

}

# ----------------------------------------------------
# -- Start of Parameter Section
# ----------------------------------------------------

# Initialise vars for getOpt ....

while ( getOpt(":?hsf:dn:vxAeEzC:b:t:N:") ) {
 if (($getOpt_optName eq "h") || ($getOpt_optName eq "?") )  {
   usage ("");
   exit;
 }
 elsif (($getOpt_optName eq "s"))  {
   $silent = "Yes";
 }
 elsif (($getOpt_optName eq "A"))  {
   if ( $silent ne "Yes") {
     print "Search will be path independent\n";
   }
   $PI = '-PI';
 }
 elsif (($getOpt_optName eq "z"))  {
   if ( $silent ne "Yes") {
     print "Check AWS S3 for backups of the uncompressed file\n";
   }
   $checkUncompressed = 1;
 }
 elsif (($getOpt_optName eq "x"))  {
   if ( $silent ne "Yes") {
     print "Eligible filenames will NOT be printed to STDOUT\n";
   }
   $printFilename = 0;
 }
 elsif (($getOpt_optName eq "b"))  {
   if ( $silent ne "Yes") {
     print "AWS S3 bucket being used is $getOpt_optValue\n";
   }
   $S3Bucket = $getOpt_optValue;
 }
 elsif (($getOpt_optName eq "t"))  {
   if ( $silent ne "Yes") {
     print "AWS S3 bucket type being used is $getOpt_optValue\n";
   }
   $S3BucketType = $getOpt_optValue;
 }
 elsif (($getOpt_optName eq "A"))  {
   if ( $compDate ne "") {
     usage ("Only one of -A, -M and -C may be used");
     exit;
   }
   if ( $silent ne "Yes") {
     print "Last accessed date will be used to compare against\n";
   }
   $compDate = "Referenced";
 }
 elsif (($getOpt_optName eq "C"))  {
   if ( $compDate ne "") {
     usage ("Only one of -A, -M and -C may be used");
     exit;
   }
   if ( $silent ne "Yes") {
     print "Created date will be used to compare against\n";
   }
   $compDate = "Created";
 }
 elsif (($getOpt_optName eq "M"))  {
   if ( $compDate ne "") {
     usage ("Only one of -A, -M and -C may be used");
     exit;
   }
   if ( $silent ne "Yes") {
     print "Last modified date will be used to compare against\n";
   }
   $compDate = "Modified";
 } 
 elsif (($getOpt_optName eq "f"))  {
   if ( $silent ne "Yes") {
     print "AWS S3 will be checked for $getOpt_optValue\n";
   }
   $inFile = $getOpt_optValue;
 }
 elsif (($getOpt_optName eq "C"))  {
   $client = "-C $getOpt_optValue";
   if ( $silent ne "Yes") {
     print "Will look for files backed up on server $getOpt_optValue\n";
   }
 }
 elsif (($getOpt_optName eq "d"))  {
   $generateDelete = 1;
   if ( $silent ne "Yes") {
     print "Delete statements will be generated\n";
   }
 }
 elsif (($getOpt_optName eq "E"))  {
   $doDelete = 1;
   if ( $silent ne "Yes") {
     print "Delete statements will be executed\n";
   }
 }
 elsif (($getOpt_optName eq "e"))  {
   $displayDelete = 1;
   if ( $silent ne "Yes") {
     print "Delete statements will be displayed\n";
   }
 }
 elsif (($getOpt_optName eq "n"))  {
   ($numBackups) = $getOpt_optValue =~ /(\d*)/;
   if ( $numBackups ne $getOpt_optValue ) {
     usage ("Parameter ${getOpt_optName}'s value should be an integer - it looks strange: $getOpt_optValue");
     exit;
   }
   if ( $silent ne "Yes") {
     print "$getOpt_optValue backups will be checked for\n";
	 print "NOTE: This parameter is ignored - only 1 backup will be checked for\n";
   }
 }
 elsif (($getOpt_optName eq "N"))  {
   ($numDays) = $getOpt_optValue =~ /(\d*)/;
   if ( $numDays ne $getOpt_optValue ) {
     usage ("Parameter ${getOpt_optName}'s value should be an integer - it looks strange: $getOpt_optValue");
     exit;
   }
   if ( $silent ne "Yes") {
     print "Files will be retained on disk for $numDays days before being eligible for removal\n";
   }
 }
 elsif (($getOpt_optName eq "v"))  {
   $debugLevel++;
   if ( $silent ne "Yes") {
     print "Debug Level set to $debugLevel\n";
   }
 }
 else { # handle other entered values ....
   usage ("Parameter $getOpt_optName : This parameter is unknown");
   exit;
 }
}

# ----------------------------------------------------
# -- End of Parameter Section
# ----------------------------------------------------

chomp $machine;
my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
my $year = 1900 + $yearOffset;
$month = $month + 1;
$hour = substr("0" . $hour, length($hour)-1,2);
$minute = substr("0" . $minute, length($minute)-1,2);
$second = substr("0" . $second, length($second)-1,2);
$month = substr("0" . $month, length($month)-1,2);
my $day = substr("0" . $dayOfMonth, length($dayOfMonth)-1,2);
my $NowTS = "$year.$month.$day $hour:$minute:$second";
my $YYYYMMDD = "$year$month$day";

if ( $compDate eq "" ) {
  $compDate = "Referenced";
}

my @return = myDate("DATE\:$YYYYMMDD");
if ($return[12] ne '' ) { # something bad has happened
  print $return[12];
  exit;
}

$todayNum = $return[5];

my %monthNumber = ( 'Jan' =>  '01', 'Feb' =>  '02', 'Mar' =>  '03', 'Apr' =>  '04', 'May' =>  '05', 'Jun' =>  '06',
                    'Jul' =>  '07', 'Aug' =>  '08', 'Sep' =>  '09', 'Oct' =>  '10', 'Nov' =>  '11', 'Dec' =>  '12',
                    'January' =>  '01', 'February' =>  '02', 'March' =>  '03', 'April' =>  '04', 'May' =>  '05', 'June' =>  '06',
                    'July' =>  '07', 'August' =>  '08', 'September' =>  '09', 'October' =>  '10', 'November' =>  '11', 'December' =>  '12' );

# generate the S3 key
my $S3Key = "$S3Bucket/$machine";
if ( $S3BucketType ne '' ) { $S3Key = "$S3Bucket/$S3BucketType/$machine"; }

# gather the files that have been backed up from this host

my %S3File = (); # clear out the array
if ( ! open ( S3FILES, "aws s3 ls s3://$S3Key --recursive |" ) ) { die "Unable to run the AWS S3 LS command\n$?\n";  }   # magic occurs here

while ( <S3FILES> ) {
  # C:\Users\db2admin>aws s3 ls s3://DEFAULT_BUCKET/1month/ADBDB1TST --recursive
  # 2018-10-02 10:59:34      12288 1month/ADBDB1TST/archivedLogs/DB2/STM1TST/NODE0000/LOGSTREAM0000/C0000008/S0006263.LOG
  # 2018-10-02 10:59:35    2048000 1month/ADBDB1TST/archivedLogs/DB2/STM1TST/NODE0000/LOGSTREAM0000/C0000008/S0006264.LOG
  chomp $_;
  my @bits = split(" ");
  my $S3FileSize = $bits[2];

  # adjust the returned file name as required
  my $S3FileName = $bits[3];
  if ( $S3FileName =~ /archivedLogs/ ) {
    ($S3FileName) = ( $S3FileName =~ /.*archivedLogs\/(.*)/ );  # just truncate everything before and including the archivedLogs/ literal
  }
  elsif ( $S3FileName =~ /backups/ ) {
    ($S3FileName) = ( $S3FileName =~ /.*backups\/(.*)/ );       # just truncate everything before and including the backups/ literal
  }
  if ( $debugLevel > 0 ) { # display the bplist output .....
    print "$bits[3]: Adding $S3FileName ($S3FileSize)\n";
  }
  $S3File{$S3FileName} = $S3FileSize;    # Associative array will have the file size as the value
}

close S3FILES;

my $pos = 0;
my $fileSize = 0;
my $lineType = 0;
my $script = '';
my $timestamp = '';
my $formatted_timestamp = '';
my %scriptStart = ();
my $cFile = '';
my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks, $a, $m, $c);

if ( $inFile eq "STDIN" ) {            # no input file was specified ....
  if (! open (INPUT,"-") )  {       # open STDIN if a file hasn't been declared
    die "Can't open STDIN! \n$!\n";
  }
  while ( <INPUT> ) { # process the input filenames
    my $file = trim($_);
    $cFile = trim($_);
    if ( $checkUncompressed ) { # strip off the last .Z from the file if it exists
      $cFile =~ s/\.Z$//;
    }
    if ( $debugLevel > 1) { print "Filename being searched for is $cFile\n"; }
	
	($fileAge, $m, $fileSize) = getFileAge($cFile);
	if ( $fileAge == -1 ) { # invalid comparison date  
	  next; 
	}
	if ( $fileAge < $numDays ) { # too young to be processed
      if ( $silent ne "Yes" ) {
	    print "File $cFile ignored as it is too young ($fileAge days old)\n";
      }
	  next;
	}
	
	# generate the name to compare against
	my $cFile_comp = $cFile;
	$cFile_comp =~ s/\\/\//g;    # convert all back slashes to forward slashes
	my $comparisonName = $cFile_comp;
    if ( $cFile_comp =~ /archivedLogs/ ) {
      ($comparisonName) = ( $cFile_comp =~ /.*archivedLogs\/(.*)/ );  # just truncate everything before and including the archivedLogs/ literal
    }
    elsif ( $cFile_comp =~ /backups/ ) {
      ($comparisonName) = ( $cFile_comp =~ /.*backups\/(.*)/ );       # just truncate everything before and including the backups/ literal
    }
    if ( $debugLevel > 1) { print "Comparison name is $comparisonName [$cFile_comp]\n"; }
   
	# to get to here the file must be of an age to be removed
    if ( defined($S3File{$comparisonName}) ) { # AWS S3 has a backup of this file
      if ( $debugLevel > 0) { print STDERR "File $comparisonName has a backup in AWS S3. File Sizes are - S3 : $S3File{$comparisonName} and on disk : $fileSize (Last updated: $m)\n"; }
	  if ( $S3File{$comparisonName} != $fileSize ) { 
	    # the files aren't the same size so do nothing
	    if ( $silent ne "Yes" ) {
          print "File $comparisonName has a backup in AWS S3 but the file sizes aren't the same - S3 : $S3File{$comparisonName} and on disk : $fileSize so it WONT be removed (Last updated: $m)\n";
		}
		next;
      }		
      if ( $silent ne "Yes" ) {
	    if ( $silent ne "Yes" ) {
          print "File $comparisonName has a backup in AWS S3 and so file is eligible for action (Last updated: $m)\n";
		}
      }
	  processActions($cFile);
	}
    else { # file wasn't found/selected
      if ( $silent ne "Yes" ) {
        print "No copies of file $comparisonName found in AWS S3 - a copy must exist (Last updated: $m)\n";
      }
    }
  }
}
else { # dont loop - just check the supplied file
  # adjust file name if necessary
  $cFile = trim($inFile);
  if ( $checkUncompressed ) { # strip off the last .Z from the file if it exists
    $cFile =~ s/\.Z$//;
  }
  if ( $debugLevel > 1) { print "Filename being searched for is $cFile\n"; }
  
  ($fileAge, $m, $fileSize) = getFileAge($cFile);
  if ( $fileAge == -1 ) { # invalid comparison date  
    exit; 
  }
  if ( $fileAge < $numDays ) { # too young to be processed
    print "File $cFile ignored as it is too young ($fileAge days old)\n";
    exit;
  }
	
  # generate the name to compare against
  my $comparisonName = $cFile;
  if ( $cFile =~ /archivedLogs/ ) {
    ($comparisonName) = ( $cFile =~ /.*archivedLogs\/(.*)/ );  # just truncate everything before and including the archivedLogs/ literal
  }
  elsif ( $cFile =~ /backups/ ) {
    ($comparisonName) = ( $cFile =~ /.*backups\/(.*)/ );       # just truncate everything before and including the backups/ literal
  }
  
  # to get to here the file must be of an age to be removed
  if ( defined($S3File{$comparisonName}) ) { # AWS S3 has a backup of this file
    if ( $S3File{$comparisonName} != $fileSize ) { 
      # the files aren't the same size so do nothing
	  if ( $silent ne "Yes" ) {
        print "File $comparisonName has a backup in AWS S3 but the file sizes aren't the same - S3 : $S3File{$comparisonName} and on disk : $fileSize so it WONT be removed (Last updated: $m)\n";
	  }
	  exit;
    }		
    if ( $silent ne "Yes" ) {
      print "File $comparisonName has a backup in AWS S3 and so file is eligible for action (Last updated: $m)\n";
    }
	processActions($cFile);
  }
  else { # file wasn't found/selected
    if ( $silent ne "Yes" ) {
      print "No copies of file $comparisonName found in AWS S3 - a copy must exist (Last updated: $m)\n";
    }
  }
  
}
