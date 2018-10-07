@echo off
REM
REM --------------------------------------------------------------------
REM removeDiskFilesCopiedToS3.bat
REM
REM $Id: removeDiskFilesCopiedToS3.bat,v 1.5 2018/10/04 05:13:00 db2admin Exp db2admin $
REM
REM Description:
REM Script to remove disk files copied to AWS S3 storage
REM
REM Usage:
REM   removeDiskFilesCopiedToS3.bat <number of days to retain> <directory to process> <TRIAL>
REM
REM $Name:  $
REM
REM ChangeLog:
REM $Log: removeDiskFilesCopiedToS3.bat,v $
REM Revision 1.5  2018/10/04 05:13:00  db2admin
REM correct the fix
REM
REM Revision 1.4  2018/10/04 02:44:52  db2admin
REM correct time when it is 12:39 PM
REM .
REM
REM Revision 1.3  2018/10/03 22:59:45  db2admin
REM make the timestamps 24 hours clocks
REM
REM Revision 1.2  2018/10/03 04:37:12  db2admin
REM alter path to include c:\udbdba\scripts
REM
REM Revision 1.1  2018/10/03 01:00:57  db2admin
REM Initial revision
REM
REM --------------------------------------------------------------------

REM Set up some variables

FOR /f "tokens=2-5 delims=/ " %%i in ('date /t') do (
  set DATE_TS=%%k-%%j-%%i
)

setlocal ENABLEDELAYEDEXPANSION
FOR /f "tokens=1-3 delims=/: " %%i in ('time /t') do (
  set TIME_TS=%%i:%%j:00
  if "%%k" == "PM" (
    if "%%i" NEQ 12 (
      set /a "Hour=%%i+12"
      set TIME_TS=!Hour!:%%j:00
	)
  )
)

set TS=%DATE_TS% %TIME_TS%

FOR /f "tokens=1-2 delims=/: " %%i in ('hostname') do (
  set machine=%%i
)

REM set default parameters as necessaru
if (%1) == () (
  set NUMDAYS=3
) else (
  set NUMDAYS=%1
)

if (%2) == () (
  set DIRECTORY=b:\
) else (
  set DIRECTORY=%2
)

if "%3" == "TRIAL" (
  set OPTIONS=-dx
) else (
  set OPTIONS=-sEex
)

set PATH=%PATH%;c:\udbdba\scripts

echo %TS% - Starting %0% >logs\removeDiskFilesCopiedToS3.log
echo %TS% - Server: %machine% >>logs\removeDiskFilesCopiedToS3.log
echo %TS% - Number of Days to Retain: %NUMDAYS% >>logs\removeDiskFilesCopiedToS3.log
echo %TS% - Directory Being Processed: %DIRECTORY% >>logs\removeDiskFilesCopiedToS3.log

dir /A:-D /S /B %DIRECTORY% | checkS3.pl -N %NUMDAYS% %OPTIONS% >>logs\removeDiskFilesCopiedToS3.log

FOR /f "tokens=2-5 delims=/ " %%i in ('date /t') do (
  set DATE_TS=%%k-%%j-%%i
)

setlocal ENABLEDELAYEDEXPANSION
FOR /f "tokens=1-3 delims=/: " %%i in ('time /t') do (
  set TIME_TS=%%i:%%j:00
  if "%%k" == "PM" (
    if "%%i" NEQ 12 (
      set /a "Hour=%%i+12"
      set TIME_TS=!Hour!:%%j:00
	)
  )
)

set TS=%DATE_TS% %TIME_TS%
echo %TS% - Finished >>logs\removeDiskFilesCopiedToS3.log
