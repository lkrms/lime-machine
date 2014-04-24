@echo off

rem Example: close_copy.cmd C:\.backup UNIQUE_REF

if "%2"=="" goto :EOF

set MOUNT_ROOT=%1
set COPY_REF=%2

set VARS_SCRIPT_PATH=%MOUNT_ROOT%\%COPY_REF%-vars.cmd
set MOUNT_SCRIPT_PATH=%MOUNT_ROOT%\%COPY_REF%-mount.cmd
set CLOSE_SCRIPT_PATH=%MOUNT_ROOT%\%COPY_REF%-close.cmd
set COPY_ROOT=%MOUNT_ROOT%\%COPY_REF%

rem Needed to escape cygwin's 32-bit sandbox.
set CMD_PATH=%WINDIR%\System32\cmd.exe
if exist %WINDIR%\Sysnative\cmd.exe set CMD_PATH=%WINDIR%\Sysnative\cmd.exe

%CMD_PATH% /c %CLOSE_SCRIPT_PATH%

set RESULT=%errorlevel%

if "%RESULT%"=="0" (

    del /f /q "%VARS_SCRIPT_PATH%" "%MOUNT_SCRIPT_PATH%" "%CLOSE_SCRIPT_PATH%"

    rmdir /s /q "%COPY_ROOT%"

)

exit /b %RESULT%

