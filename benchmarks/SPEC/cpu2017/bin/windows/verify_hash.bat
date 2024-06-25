@if not defined SPEC_BATCH_DEBUG echo off
rem
rem verify_hash.bat
rem
rem Copyright 1999-2020 Standard Performance Evaluation Corporation
rem
rem $Id$
rem

setlocal
set args=%*
if "verify_hash"=="port_progress" (
    set args=
    FOR %%D IN (%*) DO call :GET_LIST %%D
)

specutil tools\verify_hash %args%
goto :EOF

:GET_LIST
   set args=%args% %1
   goto :EOF

rem Editor settings: (please leave this at the end of the file)
rem vim: set filetype=dosbatch syntax=dosbatch shiftwidth=4 tabstop=8 expandtab nosmarttab:
