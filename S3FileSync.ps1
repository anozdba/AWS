# --------------------------------------------------------------------
# S3FileSync.ps1
#
# $Id: S3FileSync.ps1,v 1.6 2018/10/03 05:47:13 db2admin Exp db2admin $
#
# Description:
# Script to ensure that all files are copied to S3 buckets
#
# Usage:
#   S3FileSync.ps1
#
# $Name:  $
#
# ChangeLog:
# $Log: S3FileSync.ps1,v $
# Revision 1.6  2018/10/03 05:47:13  db2admin
# change timestamps to have 24 hours hours
#
# Revision 1.5  2018/10/03 05:21:40  db2admin
# modify the error out file to be more specific
#
# Revision 1.4  2018/10/03 04:12:23  db2admin
# 1. Allow lines in output to go to 500 characters before wrapping
# 2. fully qualify the AWS executable
#
# Revision 1.3  2018/10/02 02:00:35  db2admin
# modify script to only gather files backed up from the server where the script is running
#
# Revision 1.2  2018/10/02 01:11:40  db2admin
# Major changes but mainly to allow to use either
# the AWS CLI or the Powershell extensions
#
# Revision 1.1  2018/09/28 08:27:40  db2admin
# Initial revision
#
#
# --------------------------------------------------------------------

# parameters

param(
  [string]$directory = "b:\" ,
  [string]$S3Bucket = "DEFAULT_BUCKET" ,
  [string]$bucketType = "",
  [string]$fileTypes = "*.dmp,*.DMP,*.bak,*.BAK,*.trn,*.TRN,*.log,*.LOG" , 
  [string]$email = 'webmaster@KAGJCM.com.au',
  [switch]$awscli = $false,
  [switch]$help = $false 
)

# Update output buffer size to prevent clipping in output
if( $Host -and $Host.UI -and $Host.UI.RawUI ) {
  $rawUI = $Host.UI.RawUI
  $oldSize = $rawUI.BufferSize
  $typeName = $oldSize.GetType( ).FullName
  $newSize = New-Object $typeName (500, $oldSize.Height)
  $rawUI.BufferSize = $newSize
}

$backupDirLength = $directory.length

$targetS3 = "$S3Bucket/$bucketType"
$targetS3_log = "$S3Bucket_$bucketType"
if ( $bucketType -eq '' ) {
  $targetS3 = "$S3Bucket"
  $targetS3_log = "$S3Bucket"
}

$interface_message = "AWS Powershell interface will be used"
if ( $awscli ) {
  write-output "AWSCLI has been set"
  $interface_message = "AWS CLI will be used"
}

# logging 

$hostname = $env:computername

# make sure the temporary file to hold the S3 filenames doesn't exist
$tmpDir = $env:temp
if ( $tmpDir -eq '' ) {
  $tmpDir = "c:\temp"
}

$S3FileNames = "$tmpDir\S3FileSync_${hostname}_${targetS3_log}_files.txt"
If (Test-Path $S3FileNames){
	Remove-Item $S3FileNames
}

$S3FileCopy = "$tmpDir\S3FileSync_${hostname}_${targetS3_log}_copy.txt"
If (Test-Path $S3FileCopy){
	Remove-Item $S3FileCopy
}

$logFile = "logs\S3FileSync_${hostname}_$targetS3_log.log"
# Create the file to log this run to (and start logging)
If (Test-Path $logFile ){
	Remove-Item $logFile
}
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Start-Transcript -path $logFile -append

if ( ! $awscli ) {
  # Get the AWS Stuff
  Import-Module -Name AWSPowerShell
}

# put in fix for early version of powershell
If ($PSVersionTable.PSVersion.Major -le 2) {
  # put in fix for STDOUT redirection
  $bindingFlags = [Reflection.BindingFlags] “Instance,NonPublic,GetField”
  $objectRef = $host.GetType().GetField(“externalHostRef”, $bindingFlags).GetValue($host)

  $bindingFlags = [Reflection.BindingFlags] “Instance,NonPublic,GetProperty”
  $consoleHost = $objectRef.GetType().GetProperty(“Value”, $bindingFlags).GetValue($objectRef, @())

  [void] $consoleHost.GetType().GetProperty(“IsStandardOutputRedirected”, $bindingFlags).GetValue($consoleHost, @())
  $bindingFlags = [Reflection.BindingFlags] “Instance,NonPublic,GetField”
  $field = $consoleHost.GetType().GetField(“standardOutputWriter”, $bindingFlags)
  $field.SetValue($consoleHost, [Console]::Out)
  $field2 = $consoleHost.GetType().GetField(“standardErrorWriter”, $bindingFlags)
  $field2.SetValue($consoleHost, [Console]::Out)
  write-output "STDOUT work around implemented for Powershell V2"
}

# Generate variables for the report

$ts = Get-Date -format yyyy-MM-dd-HH:mm
$scriptName = $myInvocation.MyCommand.Name
$env:DB2INSTANCE=$instance

# validate input

if ( $help ) {
  write-output "This script will synchronise files in the specified directory and the specified S3 bucket/folder"
  write-output ""
  write-output "Parameters that have been set are:"
  write-output ""
  write-output "  Directory          : $directory"
  write-output "  S3Bucket           : $S3bucket"
  write-output "  Bucket Type/Folder : $bucketType"
  write-output "  File Types         : $fileTypes"
  write-output "  Email              : $email"
  write-output "  Interface to use   : $interface_message"
  write-output ""
  write-output "Command invocation format is:"
  write-output ""
  write-output "  S#FileSync.ps1 [-directory <directory>] [-S3Bucket <bucket name>] [-bucketType <folder name>] [-email <email address>] [-fileTypes <files>] [-awscli]"
  write-output ""
  write-output "      directory          - directory to use [Default: b:\]"
  write-output "      S3Bucket           - Main S3 bucket [Default: DEFAULT_BUCKET]"
  write-output "      bucketType         - qualifies the bucket type to identify the storage area/life cycle policy [Default: DFT_development]"
  write-output "      fileTypes          - qualifies the types of files to be processed [Default: *.dmp,*.DMP,*.bak,*.BAK,*.trn,*.TRN,*.log,*.LOG]"
  write-output "      Email to send MSG  - email address to send emails to [Default: mpl_dba]"
  write-output "      aws cli            - Use the base AWS CLI to talk to S3 rather than the powershell modules [Default: Powershell]"
  write-output "      help               - This message"
  write-output ""
  Stop-Transcript
  return
}

$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts Starting $scriptName"

$send_email = $false

$exitCode = 0

# start the process
$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts Copy files in $directory to S3 Bucket $targetS3"

# Get a list of backups in the provided S3 bucket for this hostname, output into a temp file
# 
if ( $awscli ) { # use the aws cli}
  start-process cmd.exe "/c `"C:\progra~1\Amazon\AWSCLI\aws s3 ls s3://$targetS3/$hostname --recursive`"" -wait -nonewwindow -RedirectStandardOutput $S3FileNames -RedirectStandardError "logs\S3FileSync_${hostname}_${targetS3}_error.out"
  write-output "Command Executed: aws s3 ls s3://$targetS3/$hostname --recursive"
  #start-process cmd.exe "/c `"aws s3 ls s3://$targetS3 `"" -wait -nonewwindow -RedirectStandardOutput $S3FileNames
}
else { # use the powershell interface
  (Get-S3Object -BucketName $targetS3/$hostname) | select-object -property key | Out-File $S3FileNames
  write-output "Command Executed: (Get-S3Object -BucketName $targetS3/$hostname) | select-object -property key | Out-File $S3FileNames"
}

$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts S3 File names copied to $S3FileNames"

# loop through the files in the selected directory ignoring directories and only selecting files that match the supplied mask
Get-ChildItem -path $directory -Include $fileTypes -recurse | Where-Object {!($_.PSIsContainer)}| ForEach-Object {

  $fileObject = Get-Item $_.FullName   # the name of the file being processed (includes the path)
  $fileName = $fileObject.Name
  $fileFullName = $fileObject.FullName
  $fileSize = $fileObject.length
  $fileDir = $fileObject.DirectoryName
  $ts = Get-Date -format yyyy-MM-dd-HH:mm
  write-output "$ts Checking if `"$fileFullName`" has been copied (Size: $fileSize)"
  
  if ( $fileDir -like '*archivedLogs*' ) { # the file being copied is a log
    # assumes that the path looks like b:\archivedLogs\dbname\... and converts it to a string 
	# with the front removed and the backsashes converted to forward slashes
	# kept logs seperate in case the destination directory changes
	$folderPos = $fileDir.IndexOf('archivedLogs')
	$folder = $fileDir.substring($folderPos+13).replace('\','/')
    $S3KeyName = $hostname + '/archivedLogs/' + $folder + '/' + $fileName
    $ts = Get-Date -format yyyy-MM-dd-HH:mm
	write-output "$ts S3 Keyname will be (archivedLogs): $S3KeyName"
  }
  else {	
	if ( $fileDir -eq $Null ) {
      $folder = ""
	  $S3KeyName = $hostname + '/' + $fileName
	}
	else {
	  if ( $fileDir -like '*backups*' ) { # check if there is a backups in the fullname
	    $folderPos = $fileDir.IndexOf('backups')
		$folder = $fileDir.substring($folderPos+8).replace('\','/')
	  }
	  else {
	    $folder = $fileDir.substring($backupDirLength).replace('\','/')
	  }
	  $S3KeyName = $hostname + '/backups/' + $folder + '/' + $fileName
	}
	write-output "$ts S3 Keyname will be (Backup File): $S3KeyName"
  }
  
  $copyFile = 0
  # now to check if it is the S3 bucket (null indicates that the filename isn't in the list of s3 files)
  if ( (Get-Content $S3FileNames | Select-String "$S3KeyName" -simplematch) -eq $Null ) { 
    $ts = Get-Date -format yyyy-MM-dd-HH:mm
    write-output "$ts File `"$S3KeyName`" not in bucket and will be copied"
    $copyFile = 1		 
  }
  else {
    $ts = Get-Date -format yyyy-MM-dd-HH:mm
    write-output "$ts File already exists in S3 bucket"
    $S3File = Get-Content $S3FileNames | select-String "$S3KeyName" -simplematch  # get the line of the match
    $S3File_Str = $S3File.line
    #Get-Content $S3FileNames | select-String "$S3KeyName" -simplematch | Select-Object 
    $S3File_Arr = $S3File_Str.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)
    $S3FileSize = $S3File_Arr[2]
	if ( $S3FileSize -ne $fileSize ) { # files are different sizes so copy the file over again
	  write-output "Files are of different sizes (S3 is $S3FileSize, Local is $fileSize) and so it will be recopied"
	  $fileCopy = 1
	}
  }
  
  if ( $copyFile ) {
  	# Copy the file out to Amazon S3 storage
	if ( $awscli ) {
	  start-process cmd.exe "/c `"C:\progra~1\Amazon\AWSCLI\aws s3 cp --no-progress --sse AES256 $fileFullName s3://$targetS3/$S3KeyName --endpoint-url https://s3-ap-southeast-2.amazonaws.com`" " -wait -nonewwindow -RedirectStandardOutput $S3FileCopy
      get-content $S3FileCopy | write-output
	}
	else {
      write-S3Object -BucketName $targetS3 -Key "$S3KeyName" -File $fileFullName
	}
    if ($?) {
      $ts = Get-Date -format yyyy-MM-dd-HH:mm
	  if ( $awscli ) {
	    write-output "$ts Upload completed: aws s3 cp --sse AES256 '$fileFullName' s3://$targetS3/$S3KeyName --endpoint-url https://s3-ap-southeast-2.amazonaws.com" 
	  }
	  else {
        write-output "$ts Upload completed: Write-S3Object -BucketName $S3Bucket -Key `"s3keyname`" -File $fileFullname" 
	  }
    } 
    else {
      # Upload failed
      $ts = Get-Date -format yyyy-MM-dd-HH:mm
      if ( $awscli ) {
	    write-output "$ts Upload failed: aws s3 cp --sse AES256 '$fileFullName' s3://$targetS3/$S3KeyName --endpoint-url https://s3-ap-southeast-2.amazonaws.com" 
	  }
	  else {
        write-output "$ts Upload failed: Write-S3Object -BucketName $S3Bucket -Key `"$s3keyname`" -File $fileFullName" 
	  }
      $exitCode = 1
    }
  }
  
}

$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts Finished $scriptName"

if ( $exitCode -eq 1 ) { # something bad happened
  # construct the body of the message
  $ts = Get-Date -format yyyy-MM-dd-HH:mm
  write-output "$ts Sending Email to $email reporting failure"
  Stop-Transcript  # stop the transcript here so that the log can be attached to the email
  write-output "results from the move of disk backups to S3 bucket $S3Bucket on $hostname `n" | Out-File $tmpDir\S3FileSync_${hostname}_${S3Bucket}_$bucketType.mailBody
  write-output "The last successful backup details are:`n" | Out-File $tmpDir\S3FileSync_${hostname}_${S3Bucket}_$bucketType.mailBody -append
  get-content $logFile | Out-File $tmpDir\S3FileSync_${hostname}_${S3Bucket}_$bucketType.mailBody -append

  $body = get-content "$tmpDir\S3FileSync_${hostname}_${S3Bucket}_$bucketType.mailBody" | Out-String

  Send-MailMessage -To "$email" -From "do_not_reply@KAGJCM.com.au" -Subject "Error - $hostname - S3 Sync of files to $S3Bucket failed" -SmtpServer smtp.KAGJCM.local -Body $body -Attachments $logFile 
}
else  {
  Stop-Transcript
}

