@echo off

rem Example: create_copy.cmd C:\.backup UNIQUE_REF C D E

if "%3"=="" goto :EOF

set WORKING_DIR=%~dp0
set MOUNT_ROOT=%1
shift
set COPY_REF=%1
shift

set ARCH_SUFFIX=
if exist "C:\Program Files (x86)" set ARCH_SUFFIX=_64

set VARS_SCRIPT_PATH=%MOUNT_ROOT%\%COPY_REF%-vars.cmd
set MOUNT_SCRIPT_PATH=%MOUNT_ROOT%\%COPY_REF%-mount.cmd
set CLOSE_SCRIPT_PATH=%MOUNT_ROOT%\%COPY_REF%-close.cmd
set VSHADOW_PATH=%WORKING_DIR%vsstools%ARCH_SUFFIX%\vshadow.exe

echo ^@echo off > %MOUNT_SCRIPT_PATH%
echo call %VARS_SCRIPT_PATH% >> %MOUNT_SCRIPT_PATH%

echo ^@echo off > %CLOSE_SCRIPT_PATH%
echo call %VARS_SCRIPT_PATH% >> %CLOSE_SCRIPT_PATH%
echo %VSHADOW_PATH% -dx=%%SHADOW_SET_ID%% >> %CLOSE_SCRIPT_PATH%
echo exit /b %%errorlevel%% >> %CLOSE_SCRIPT_PATH%

set COUNT=0
set VOLUMES=

:whileVol
if "%1"=="" goto endWhileVol

if %COUNT%==0 (
    set VOLUMES=%1:
) else (
    set VOLUMES=%VOLUMES% %1:
)

set /a COUNT+=1

set VOL_MOUNT=%MOUNT_ROOT%\%COPY_REF%\%1
if not exist %VOL_MOUNT% mkdir %VOL_MOUNT%

echo %VSHADOW_PATH% -el=%%SHADOW_ID_%COUNT%%%,%VOL_MOUNT% >> %MOUNT_SCRIPT_PATH%

shift

goto whileVol
:endWhileVol

rem Needed to escape cygwin's 32-bit sandbox.
%WINDIR%\Sysnative\cmd.exe /c %VSHADOW_PATH% -p -script=%VARS_SCRIPT_PATH% -exec=%MOUNT_SCRIPT_PATH% %VOLUMES%

exit /b %errorlevel%
