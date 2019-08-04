# --------------------------------------------------------------------
# S3FileInventory.ps1
#
# $Id: S3FileInventory.ps1,v 1.4 2019/01/09 02:44:44 db2admin Exp db2admin $
#
# Description:
# Script to list a S3 file inventory for a server for a specified bucket
#
# Usage:
#   S3FileInventory.ps1
#
# $Name:  $
#
# ChangeLog:
# $Log: S3FileInventory.ps1,v $
# Revision 1.4  2019/01/09 02:44:44  db2admin
# add in a -prefix parameter to provide prefix information
#
# Revision 1.3  2019/01/09 01:13:12  db2admin
# add in aswapi switch to allow retrieval of 'storage class' which will indicate if an object is in glacier or not
#
# Revision 1.2  2019/01/08 03:54:29  db2admin
# get rid of unnecessary parameters
#
# Revision 1.1  2019/01/08 00:47:41  db2admin
# Initial revision
#
#
# --------------------------------------------------------------------

# parameters

param(
  [string]$S3Bucket = "DEFAULT_BUCKET" ,
  [string]$bucketType = "",
  [string]$filter = "",
  [string]$server = $env:computername,
  [string]$email = 'webmaster@KAGJCM.com.au',
  [string]$prefix = '',
  [switch]$awscli = $false,
  [switch]$awsapi = $false,
  [switch]$command = $false,
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
if ( $awsapi ) { 
  write-output "AWSAPI has been set - AWS S3API will be used"
  $interface_message = "AWS S3API will be used"
}
elseif ( $awscli ) {
  write-output "AWSCLI has been set - AWS S3 will be used"
  $interface_message = "AWS S3 will be used"
}

if ( $command ) {
  write-output "AWS Commands will be displayed"
}

# logging 

$hostname = $server

# make sure the temp directory variable is set
$tmpDir = $env:temp
if ( $tmpDir -eq '' ) {
  $tmpDir = "c:\temp"
}

# make sure the temporary file to hold the S3 filenames doesn't exist
$S3FileNames = "$tmpDir\S3FileInventory_${hostname}_${targetS3_log}_files.txt"
If (Test-Path $S3FileNames){
	Remove-Item $S3FileNames
}

# make sure the temporary file to hold the S3 lifecycle folder names exists
$S3LifeCycles = "$tmpDir\S3FileInventory_${hostname}_${targetS3_log}_LifeCycles.txt"
If (Test-Path $S3LifeCycles){
	Remove-Item $S3LifeCycles
}

$logFile = "logs\S3FileInventory_${hostname}_${targetS3_log}.log"
# Create the file to log this run to (and start logging)
If (Test-Path $logFile ){
	Remove-Item $logFile
}
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
write-Output $logFile
Start-Transcript -path $logFile -append

if ( ! $awscli ) {
  # Get the AWS Stuff
  Import-Module -Name AWSPowerShell
}

# put in fix for early version of powershell
If ($PSVersionTable.PSVersion.Major -le 2) {
  # put in fix for STDOUT redirection
  $bindingFlags = [Reflection.BindingFlags] "Instance,NonPublic,GetField"
  $objectRef = $host.GetType().GetField("externalHostRef", $bindingFlags).GetValue($host)

  $bindingFlags = [Reflection.BindingFlags] "Instance,NonPublic,GetProperty"
  $consoleHost = $objectRef.GetType().GetProperty("Value", $bindingFlags).GetValue($objectRef, @())

  [void] $consoleHost.GetType().GetProperty("IsStandardOutputRedirected", $bindingFlags).GetValue($consoleHost, @())
  $bindingFlags = [Reflection.BindingFlags] "Instance,NonPublic,GetField"
  $field = $consoleHost.GetType().GetField("standardOutputWriter", $bindingFlags)
  $field.SetValue($consoleHost, [Console]::Out)
  $field2 = $consoleHost.GetType().GetField("standardErrorWriter", $bindingFlags)
  $field2.SetValue($consoleHost, [Console]::Out)
  write-output "STDOUT work around implemented for Powershell V2"
}

# Generate variables for the report

$ts = Get-Date -format yyyy-MM-dd-HH:mm
$scriptName = $myInvocation.MyCommand.Name
$env:DB2INSTANCE=$instance

# validate input

if ( $help ) {
  write-output "This script will list out files for the selected server in s3"
  write-output ""
  write-output "Parameters that have been set are:"
  write-output ""
  write-output "  S3Bucket           : $S3bucket"
  write-output "  Bucket Type/Folder : $bucketType"
  write-output "  Interface to use   : $interface_message"
  write-output "  Server             : $server"
  write-output "  Filter             : $filter"
  write-output "  Prefix             : $prefix"
  write-output ""
  write-output "Command invocation format is:"
  write-output ""
  write-output "  S3FileInventory.ps1 [-S3Bucket <bucket name>] [-bucketType <folder name>] [-awscli|-awsapi] [-command] [-filter <string>]"
  write-output ""
  write-output "      S3Bucket           - Main S3 bucket [Default: DEFAULT_BUCKET]"
  write-output "      bucketType         - qualifies the bucket type to identify the life cycle policy [Default: DFT_development]"
  write-output "      Email to send MSG  - email address to send emails to [Default: mpl_dba]"
  write-output "      awscli             - Use the base AWS CLI to talk to S3 rather than the powershell modules [Default: Powershell]"
  write-output "      awsapi             - Use the base AWS CLI API to talk to S3 rather than the powershell modules [Default: Powershell]"
  write-output "      server             - server to create the inventory for [Default: computer command run from]"
  write-output "      filter             - string to filter files on (could be database name) [Default: list all selected file types]"
  write-output "      prefix             - provides the prefix of the files being looked for - if not provided a prefix will be generated from"
  write-output "                           the other provided parameters"
  write-output "      command            - switch to display the AWS commands being executed"
  write-output "      help               - This message"
  write-output ""
  Stop-Transcript
  return
}

$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts Starting $scriptName"

# start the process
$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts S3 File Inventory of $hostname"

# the bucket format being listed assumes that the structure of files is
#    //bucket_name/lifecycle_type/server/......
# so we need to obtain the lifecycle types to loop through
if ( $prefix -ne '' ) { # create a dummy entry in the loop file
  "       PRE $prefix/" | Out-File $S3LifeCycles
}
elseif ( $bucketType -ne '' ) { # create a dummy entry in the loop file
  "       PRE $bucketType/" | Out-File $S3LifeCycles
}
else { # obtain a list of lifecycles from AWS
  if ( $awscli -or $awsapi ) { # use the aws cli}
    start-process cmd.exe "/c `"C:\progra~1\Amazon\AWSCLI\aws s3 ls s3://$targetS3 `"" -wait -nonewwindow -RedirectStandardOutput $S3LifeCycles -RedirectStandardError "logs\S3FileInventory_${hostname}_${targetS3}_error.out"
	if ( $command) { 
      write-output "Command Executed: aws s3 ls s3://$targetS3"
	}
  }
  else { # use the powershell interface
    (Get-S3Object -BucketName $targetS3) | select-object -property key | Out-File $S3LifeCycles
	if ( $command) { 
      write-output "Command Executed: (Get-S3Object -BucketName $targetS3) | select-object -property key | Out-File $S3FileNames"
	}
  }
}

$searchPrefix = ''
write-output "Processing the following lifecycle folders: "
foreach($line in Get-Content $S3LifeCycles) {
  if($line -like '*PRE*' ){
    # identify the lifecycle bucket to search in 
	$mySplit = $line.Split(" ",[StringSplitOptions]'RemoveEmptyEntries')
	$tmp = $mySplit[1]
    if ( $command ) { 	
      write-output "**** LifeCycle bucket: $tmp [output in $S3FileNames]"
	}
	else {
      write-output "**** LifeCycle bucket: $tmp"
	}
	$mysplit[1] = $mySplit[1] -replace '[/]',''
	if ( $prefix -eq '' ) {
	  if ( $backupType -eq '' ) {
	    $tmp = $targetS3,$mySplit[1],$server -join "/"
	  }
	  else { # a bucket type was specified so dont use the generated targetS3 variable
	    $tmp = $S3Bucket,$mySplit[1],$server -join "/"
	  }
	}
	else {
	  $tmp = $S3Bucket,$prefix -join "/"
	}
    if ( $awsapi ) { # use the aws cli
	  if ( $prefix -eq '' ) {
        if ( $server -ne '' ) {
          $searchPrefix = $mySplit[1],$server -join "/"
        }
        else {
          $searchPrefix = $mySplit[1]
        }
      }
	  else {
	    $searchPrefix = $prefix
      }
      start-process cmd.exe "/c `"C:\progra~1\Amazon\AWSCLI\aws s3api list-objects --bucket $S3bucket --prefix $searchPrefix --output text`"" -wait -nonewwindow -RedirectStandardOutput $S3FileNames -RedirectStandardError "logs\S3FileInventory_${hostname}_${targetS3}_error.out"
   	  if ( $command) { 
        write-output "Command Executed: aws s3api list-objects --bucket $S3bucket --prefix $prefix --output text"
      }
    }
    elseif ( $awscli ) { # use the aws cli
      start-process cmd.exe "/c `"C:\progra~1\Amazon\AWSCLI\aws s3 ls s3://$tmp --recursive`"" -wait -nonewwindow -RedirectStandardOutput $S3FileNames -RedirectStandardError "logs\S3FileInventory_${hostname}_${targetS3}_error.out"
   	  if ( $command) { 
        write-output "Command Executed: aws s3 ls s3://$tmp --recursive"
      }
    }
    else { # use the powershell interface
      (Get-S3Object -BucketName $tmp) | select-object -property key | Out-File $S3FileNames
  	  if ( $command) { 
        write-output "Command Executed: (Get-S3Object -BucketName $targetS3) | select-object -property key | Out-File $S3FileNames"
	  }
    }
    
    if ( $awsapi ) { # data formatted for the API
      foreach($content in Get-Content $S3FileNames) {
        if ( $content -like 'CONTENT*' ) {
          $mySplit = $content -split '\s+'
          $tmp = $mySplit[2],$mySplit[3],$mySplit[4],$mySplit[5] -join " "
		  if ( $filter -ne '' ) {
		    if ( $tmp -like "*$filter*" ) {
              Write-Output $tmp          
	        }
		  }
		  else { # just print the data
		    Write-Output $tmp
		  }
        }
      }
    }
    else {
      if ( $filter -eq '' ) {
	    Get-Content $S3FileNames
	  }
	  else {
	    Get-Content $S3FileNames | select-string  "$filter"
	  }
    }
  }
}

# Finish up the script

$ts = Get-Date -format yyyy-MM-dd-HH:mm
write-output "$ts"
write-output "$ts Finished $scriptName"

Stop-Transcript

