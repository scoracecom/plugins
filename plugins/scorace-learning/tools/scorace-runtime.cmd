@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCORACE_PROGRAM_VERSION=unknown"
set "SCORACE_ERROR_CODE="
set "SCORACE_ERROR_SUMMARY="
set "SCORACE_STAGE="
set "SCORACE_INSTALL_LOCK="
set "SCORACE_LOCK_OWNED=0"
set "SCORACE_PAYLOAD_COUNT=0"
set "SCORACE_SCRIPT_DIR=%~dp0"
for %%I in ("%~dp0..") do set "SCORACE_PLUGIN_ROOT=%%~fI"
set "SCORACE_MANIFEST_PATH=%SCORACE_PLUGIN_ROOT%\.codex-plugin\plugin.json"
set "SCORACE_LOCK_PATH=%SCORACE_PLUGIN_ROOT%\.scorace\runtime-lock.json"
set "SCORACE_PROJECTION_PATH=%SCORACE_PLUGIN_ROOT%\.scorace\runtime-lock.windows.cmd"
set "SCORACE_SYSTEM_ROOT=%SystemRoot%"
set "SCORACE_CERTUTIL=%SystemRoot%\System32\certutil.exe"
set "SCORACE_CURL=%SystemRoot%\System32\curl.exe"
set "SCORACE_TAR=%SystemRoot%\System32\tar.exe"
set "SCORACE_TIMEOUT=%SystemRoot%\System32\timeout.exe"
set "SCORACE_FC=%SystemRoot%\System32\fc.exe"
set "SCORACE_ALL_ARGS=%*"
set "SCORACE_COMMAND=%~1"
set "SCORACE_ARG2=%~2"
set "SCORACE_ARG3=%~3"
set "SCORACE_ARG4=%~4"
set "SCORACE_RUNTIME_INVOKED=0"
set "SCORACE_RUN_EXIT_CODE=1"
set "SCORACE_BANG_PATH_INPUT=%SCORACE_PLUGIN_ROOT%"
call :reject_bang_path
if errorlevel 1 (
  set "SCORACE_ERROR_CODE=path_unsupported"
  set "SCORACE_ERROR_SUMMARY=Paths containing ! are not supported by the Windows helper"
  call :emit_error
  exit /b 1
)
set "SCORACE_BANG_PATH_INPUT=%SCORACE_RUNTIME_ROOT%"
call :reject_bang_path
if errorlevel 1 (
  set "SCORACE_ERROR_CODE=path_unsupported"
  set "SCORACE_ERROR_SUMMARY=Paths containing ! are not supported by the Windows helper"
  call :emit_error
  exit /b 1
)
if not defined SCORACE_RUNTIME_ROOT (
  set "SCORACE_BANG_PATH_INPUT=%LOCALAPPDATA%"
  if not defined SCORACE_BANG_PATH_INPUT set "SCORACE_BANG_PATH_INPUT=%USERPROFILE%"
  call :reject_bang_path
  if errorlevel 1 (
    set "SCORACE_ERROR_CODE=path_unsupported"
    set "SCORACE_ERROR_SUMMARY=Paths containing ! are not supported by the Windows helper"
    call :emit_error
    exit /b 1
  )
)
if /i "%SCORACE_COMMAND%"=="prepare" if /i "%SCORACE_ARG2%"=="--archive" (
  set "SCORACE_BANG_PATH_INPUT=%SCORACE_ARG3%"
  call :reject_bang_path
  if errorlevel 1 (
    set "SCORACE_ERROR_CODE=path_unsupported"
    set "SCORACE_ERROR_SUMMARY=Paths containing ! are not supported by the Windows helper"
    call :emit_error
    exit /b 1
  )
)
setlocal EnableDelayedExpansion

if /i "!SCORACE_COMMAND!"=="check" call :dispatch_check
if /i "!SCORACE_COMMAND!"=="check" goto :dispatch_result
if /i "!SCORACE_COMMAND!"=="prepare" call :dispatch_prepare
if /i "!SCORACE_COMMAND!"=="prepare" goto :dispatch_result
if /i "!SCORACE_COMMAND!"=="run" call :dispatch_run
if /i "!SCORACE_COMMAND!"=="run" if "!SCORACE_RUNTIME_INVOKED!"=="1" exit /b !SCORACE_RUN_EXIT_CODE!
if /i "!SCORACE_COMMAND!"=="run" goto :dispatch_result
set "SCORACE_ERROR_CODE=invalid_command"
set "SCORACE_ERROR_SUMMARY=usage: scorace-runtime.cmd check^|prepare --allow-download^|prepare --archive ZIP^|run scorace-command"
goto :dispatch_result

:dispatch_check
if defined SCORACE_ARG2 (
  call :set_error invalid_command "check takes no arguments"
  exit /b 1
)
call :validate_common
if errorlevel 1 exit /b 1
call :validate_installed
if errorlevel 1 exit /b 1
call :emit_check
exit /b 0

:dispatch_prepare
set "SCORACE_PREPARE_MODE="
set "SCORACE_ARCHIVE_SOURCE="
if /i "!SCORACE_ARG2!"=="--allow-download" if not defined SCORACE_ARG3 set "SCORACE_PREPARE_MODE=download"
if /i "!SCORACE_ARG2!"=="--archive" if defined SCORACE_ARG3 if not defined SCORACE_ARG4 (
  set "SCORACE_PREPARE_MODE=archive"
  set "SCORACE_ARCHIVE_SOURCE=!SCORACE_ARG3!"
)
if not defined SCORACE_PREPARE_MODE (
  call :set_error invalid_command "prepare requires --allow-download or --archive"
  exit /b 1
)
if /i "%SCORACE_PREPARE_MODE%"=="archive" (
  call :assert_absolute "%SCORACE_ARCHIVE_SOURCE%"
  if errorlevel 1 (
    call :set_error invalid_command "prepare --archive requires one absolute ZIP path"
    exit /b 1
  )
)
call :prepare_runtime
if errorlevel 1 (
  call :cleanup
  exit /b 1
)
call :cleanup
call :emit_prepare
exit /b 0

:dispatch_run
if not defined SCORACE_ARG2 (
  call :set_error invalid_command "run requires a scorace command"
  exit /b 1
)
call :validate_common
if errorlevel 1 exit /b 1
call :validate_installed
if errorlevel 1 exit /b 1
call :prepare_run_environment
if errorlevel 1 exit /b 1
set "SCORACE_RUNTIME_INVOKED=1"
setlocal DisableDelayedExpansion
set "SCORACE_RUN_ARGS=%SCORACE_ALL_ARGS:* =%"
"%SCORACE_EXECUTABLE%" %SCORACE_RUN_ARGS%
set "SCORACE_RUN_EXIT_CODE=%ERRORLEVEL%"
endlocal & set "SCORACE_RUN_EXIT_CODE=%SCORACE_RUN_EXIT_CODE%"
exit /b %SCORACE_RUN_EXIT_CODE%

:dispatch_result
if errorlevel 1 call :emit_error
if errorlevel 1 exit /b 1
exit /b 0

:emit_check
set "SCORACE_JSON_EXECUTABLE=%SCORACE_EXECUTABLE:\=/%"
echo {"status":"ok","operation":"runtime.check","ready":true,"program":"scorace","program_version":"%SCORACE_PROGRAM_VERSION%","target":"windows-x64","executable":"%SCORACE_JSON_EXECUTABLE%"}
exit /b 0

:emit_prepare
set "SCORACE_JSON_EXECUTABLE=%SCORACE_EXECUTABLE:\=/%"
echo {"status":"ok","operation":"runtime.prepare","ready":true,"result":"%SCORACE_PREPARE_RESULT%","program":"scorace","program_version":"%SCORACE_PROGRAM_VERSION%","target":"windows-x64","executable":"%SCORACE_JSON_EXECUTABLE%"}
exit /b 0

:emit_error
if not defined SCORACE_ERROR_CODE set "SCORACE_ERROR_CODE=runtime_error"
if not defined SCORACE_ERROR_SUMMARY set "SCORACE_ERROR_SUMMARY=Runtime helper failed"
>&2 echo {"status":"error","code":"%SCORACE_ERROR_CODE%","summary":"%SCORACE_ERROR_SUMMARY%","details":{"program":"scorace","program_version":"%SCORACE_PROGRAM_VERSION%"}}
exit /b 1

:prepare_runtime
call :validate_common
if errorlevel 1 exit /b 1
call :ensure_runtime_root
if errorlevel 1 exit /b 1
call :acquire_install_lock
if errorlevel 1 exit /b 1
call :validate_installed
if not errorlevel 1 (
  set "SCORACE_PREPARE_RESULT=reused"
  exit /b 0
)
set "SCORACE_ERROR_CODE="
set "SCORACE_ERROR_SUMMARY="
call :new_stage
if errorlevel 1 exit /b 1
set "SCORACE_ARCHIVE_COPY=%SCORACE_STAGE%\runtime.zip"
if /i "%SCORACE_PREPARE_MODE%"=="download" (
  "%SCORACE_CURL%" --fail --location --silent --show-error --proto "=https" --tlsv1.2 --output "%SCORACE_ARCHIVE_COPY%" "%P_ARCHIVE_URL%" >nul 2>&1
  if errorlevel 1 (
    call :set_error download_failed "Runtime archive download failed"
    exit /b 1
  )
) else (
  if not exist "%SCORACE_ARCHIVE_SOURCE%" if not exist "%SCORACE_ARCHIVE_SOURCE%\*" (
    call :set_error archive_invalid "Runtime archive is missing"
    exit /b 1
  )
  if exist "%SCORACE_ARCHIVE_SOURCE%\*" (
    call :set_error archive_invalid "Runtime archive must be a regular file"
    exit /b 1
  )
  call :assert_no_reparse "%SCORACE_ARCHIVE_SOURCE%"
  if errorlevel 1 (
    call :set_error archive_invalid "Runtime archive contains a reparse point"
    exit /b 1
  )
  copy /b "%SCORACE_ARCHIVE_SOURCE%" "%SCORACE_ARCHIVE_COPY%" >nul 2>&1
  if errorlevel 1 (
    call :set_error archive_invalid "Runtime archive cannot be staged"
    exit /b 1
  )
)
call :verify_archive_file "%SCORACE_ARCHIVE_COPY%"
if errorlevel 1 exit /b 1
call :validate_archive_entries
if errorlevel 1 (
  if not defined SCORACE_ERROR_CODE call :set_error archive_invalid "Runtime archive structure is invalid"
  exit /b 1
)
call :extract_archive
if errorlevel 1 exit /b 1
set "SCORACE_FAILURE_CODE=archive_invalid"
call :verify_payload_tree "%SCORACE_CANDIDATE%" archive_invalid
if errorlevel 1 exit /b 1
set "SCORACE_EXECUTABLE=%SCORACE_CANDIDATE%\%P_EXECUTABLE_PATH:/=\%"
call :verify_version "%SCORACE_EXECUTABLE%"
if errorlevel 1 exit /b 1
call :publish_candidate
if errorlevel 1 exit /b 1
set "SCORACE_PREPARE_RESULT=installed"
exit /b 0

:validate_common
call :check_tools
if errorlevel 1 exit /b 1
call :check_plugin
if errorlevel 1 exit /b 1
call :load_projection
if errorlevel 1 exit /b 1
call :validate_projection
if errorlevel 1 exit /b 1
call :load_runtime_paths
if errorlevel 1 exit /b 1
call :validate_platform
if errorlevel 1 exit /b 1
call :hash_file "%SCORACE_LOCK_PATH%" SCORACE_ACTUAL_LOCK_SHA
if errorlevel 1 (
  call :set_error runtime_lock_invalid "Runtime lock digest could not be read"
  exit /b 1
)
if /i not "%SCORACE_ACTUAL_LOCK_SHA%"=="%P_LOCK_SHA256%" (
  call :set_error runtime_lock_invalid "Runtime lock projection does not match runtime-lock.json"
  exit /b 1
)
exit /b 0

:check_tools
for %%I in ("%SCORACE_SYSTEM_ROOT%" "%SCORACE_CERTUTIL%" "%SCORACE_CURL%" "%SCORACE_TAR%" "%SCORACE_TIMEOUT%" "%SCORACE_FC%") do if not exist "%%~fI" (
  call :set_error runtime_root_unavailable "Required Windows system tool is unavailable"
  exit /b 1
)
exit /b 0

:check_plugin
for %%I in ("%SCORACE_MANIFEST_PATH%" "%SCORACE_LOCK_PATH%" "%SCORACE_PROJECTION_PATH%" "%SCORACE_SCRIPT_DIR%scorace-runtime.cmd" "%SCORACE_PLUGIN_ROOT%\tools\scorace-runtime.sh" "%SCORACE_PLUGIN_ROOT%\learning-release.json" "%SCORACE_PLUGIN_ROOT%\README.md" "%SCORACE_PLUGIN_ROOT%\LICENSE" "%SCORACE_PLUGIN_ROOT%\THIRD_PARTY_NOTICES.md") do if not exist "%%~fI" (
  call :set_error plugin_incomplete "Plugin resource is missing"
  exit /b 1
)
if exist "%SCORACE_MANIFEST_PATH%\*" (
  call :set_error plugin_incomplete "Plugin manifest must be a regular file"
  exit /b 1
)
if exist "%SCORACE_LOCK_PATH%\*" (
  call :set_error plugin_incomplete "Runtime lock must be a regular file"
  exit /b 1
)
if exist "%SCORACE_PROJECTION_PATH%\*" (
  call :set_error plugin_incomplete "Windows runtime lock projection must be a regular file"
  exit /b 1
)
for /f "delims=" %%L in ('dir /aL /s /b "%SCORACE_PLUGIN_ROOT%" 2^>nul') do (
  call :set_error plugin_incomplete "Public Plugin contains a reparse point"
  exit /b 1
)
exit /b 0

:load_projection
for %%K in (SCHEMA LOCK_SHA256 PLUGIN_ID PLUGIN_VERSION PROGRAM PROGRAM_VERSION CLI_CONTRACT LEARNING_API STATE_CONTRACT STATE_LEGACY_READ STATE_WRITE_POLICY SOURCE_REVISION SOURCE_TREE_SHA256 FEATURE_STUDY FEATURE_READ_SOURCE FEATURE_STDIO_MCP TARGET_OS TARGET_ARCH TARGET_OS_MAJOR_MIN TARGET_OS_MAJOR_MAX SYSTEM_TRUST_KIND ARCHIVE_URL ARCHIVE_SHA256 ARCHIVE_BYTES ARCHIVE_FORMAT ARCHIVE_ROOT EXECUTABLE_PATH EXECUTABLE_SHA256 EXECUTABLE_BYTES) do (
  set "P_%%K="
  set "P_SEEN_%%K="
)
set "SCORACE_PROJECTION_ERROR="
set "SCORACE_PROJECTION_KEY="
set "SCORACE_PROJECTION_VALUE="
set "SCORACE_PAYLOAD_COUNT=0"
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%SCORACE_PROJECTION_PATH%") do (
  set "SCORACE_PROJECTION_KEY=%%A"
  set "SCORACE_PROJECTION_VALUE=%%B"
  call :projection_line
  if errorlevel 1 set "SCORACE_PROJECTION_ERROR=1"
)
if defined SCORACE_PROJECTION_ERROR (
  call :set_error runtime_lock_invalid "Windows runtime lock projection is invalid"
  exit /b 1
)
for %%K in (SCHEMA LOCK_SHA256 PLUGIN_ID PLUGIN_VERSION PROGRAM PROGRAM_VERSION CLI_CONTRACT LEARNING_API STATE_CONTRACT STATE_LEGACY_READ STATE_WRITE_POLICY SOURCE_REVISION SOURCE_TREE_SHA256 FEATURE_STUDY FEATURE_READ_SOURCE FEATURE_STDIO_MCP TARGET_OS TARGET_ARCH TARGET_OS_MAJOR_MIN TARGET_OS_MAJOR_MAX SYSTEM_TRUST_KIND ARCHIVE_URL ARCHIVE_SHA256 ARCHIVE_BYTES ARCHIVE_FORMAT ARCHIVE_ROOT EXECUTABLE_PATH EXECUTABLE_SHA256 EXECUTABLE_BYTES) do if not defined P_SEEN_%%K (
  call :set_error runtime_lock_invalid "Windows runtime lock projection is incomplete"
  exit /b 1
)
if "%SCORACE_PAYLOAD_COUNT%"=="0" (
  call :set_error runtime_lock_invalid "Runtime payload is incomplete"
  exit /b 1
)
exit /b 0

:projection_line
set "SCORACE_KNOWN="
for %%K in (schema lock_sha256 plugin_id plugin_version program program_version cli_contract learning_api state_contract state_legacy_read state_write_policy source_revision source_tree_sha256 feature_study feature_read_source feature_stdio_mcp target_os target_arch target_os_major_min target_os_major_max system_trust_kind archive_url archive_sha256 archive_bytes archive_format archive_root executable_path executable_sha256 executable_bytes payload) do if /i "%SCORACE_PROJECTION_KEY%"=="%%K" set "SCORACE_KNOWN=1"
if not defined SCORACE_KNOWN exit /b 1
if /i not "%SCORACE_PROJECTION_KEY%"=="payload" if defined P_SEEN_%SCORACE_PROJECTION_KEY% exit /b 1
if /i not "%SCORACE_PROJECTION_KEY%"=="payload" set "P_SEEN_%SCORACE_PROJECTION_KEY%=1"
if /i not "%SCORACE_PROJECTION_KEY%"=="payload" (
  set "P_%SCORACE_PROJECTION_KEY%=%SCORACE_PROJECTION_VALUE%"
  exit /b 0
)
set /a SCORACE_PAYLOAD_COUNT+=1
set "SCORACE_PAYLOAD_PATH="
set "SCORACE_PAYLOAD_SHA256="
set "SCORACE_PAYLOAD_BYTES="
set "SCORACE_PAYLOAD_ROLE="
set "SCORACE_PAYLOAD_EXTRA="
for /f "tokens=1-5 delims=|" %%A in ("%SCORACE_PROJECTION_VALUE%") do (
  set "SCORACE_PAYLOAD_PATH=%%A"
  set "SCORACE_PAYLOAD_SHA256=%%B"
  set "SCORACE_PAYLOAD_BYTES=%%C"
  set "SCORACE_PAYLOAD_ROLE=%%D"
  set "SCORACE_PAYLOAD_EXTRA=%%E"
)
if not defined SCORACE_PAYLOAD_PATH exit /b 1
if not defined SCORACE_PAYLOAD_SHA256 exit /b 1
if not defined SCORACE_PAYLOAD_BYTES exit /b 1
if not defined SCORACE_PAYLOAD_ROLE exit /b 1
if defined SCORACE_PAYLOAD_EXTRA exit /b 1
set "P_PAYLOAD_%SCORACE_PAYLOAD_COUNT%_PATH=%SCORACE_PAYLOAD_PATH%"
set "P_PAYLOAD_%SCORACE_PAYLOAD_COUNT%_SHA256=%SCORACE_PAYLOAD_SHA256%"
set "P_PAYLOAD_%SCORACE_PAYLOAD_COUNT%_BYTES=%SCORACE_PAYLOAD_BYTES%"
set "P_PAYLOAD_%SCORACE_PAYLOAD_COUNT%_ROLE=%SCORACE_PAYLOAD_ROLE%"
exit /b 0

:load_runtime_paths
set "SCORACE_LOCAL_APPDATA=%LOCALAPPDATA%"
if not defined SCORACE_LOCAL_APPDATA set "SCORACE_LOCAL_APPDATA=%USERPROFILE%"
if not defined SCORACE_LOCAL_APPDATA (
  call :set_error runtime_root_unavailable "LOCALAPPDATA is unavailable"
  exit /b 1
)
if defined SCORACE_RUNTIME_ROOT (
  set "SCORACE_RAW_RUNTIME_ROOT=%SCORACE_RUNTIME_ROOT%"
) else (
  set "SCORACE_RAW_RUNTIME_ROOT=%SCORACE_LOCAL_APPDATA%\ScorAce\runtime\scorace"
)
call :assert_absolute "%SCORACE_RAW_RUNTIME_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime root must be absolute"
  exit /b 1
)
for %%I in ("%SCORACE_RAW_RUNTIME_ROOT%") do set "SCORACE_RUNTIME_ROOT=%%~fI"
call :assert_no_reparse "%SCORACE_RUNTIME_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime path contains a reparse point"
  exit /b 1
)
exit /b 0

:validate_platform
set "SCORACE_ARCH=%PROCESSOR_ARCHITEW6432%"
if not defined SCORACE_ARCH set "SCORACE_ARCH=%PROCESSOR_ARCHITECTURE%"
if /i not "%SCORACE_ARCH%"=="AMD64" if /i not "%SCORACE_ARCH%"=="ARM64" (
  set "SCORACE_ERROR_CODE=platform_unsupported"
  set "SCORACE_ERROR_SUMMARY=This Plugin supports Windows 11 x64 runtime on AMD64 or ARM64 x64 emulation"
  exit /b 1
)
set "SCORACE_VER="
set "SCORACE_VER_MAJOR="
set "SCORACE_VER_BUILD="
set "SCORACE_VER_BUILD_NUMBER=0"
for /f "tokens=2 delims=[]" %%V in ('ver') do set "SCORACE_VER=%%V"
for /f "tokens=2,4 delims=. " %%A in ("%SCORACE_VER%") do (
  set "SCORACE_VER_MAJOR=%%A"
  set "SCORACE_VER_BUILD=%%B"
)
set /a SCORACE_VER_BUILD_NUMBER=%SCORACE_VER_BUILD% 2>nul
if not "%SCORACE_VER_MAJOR%"=="10" (
  call :set_error platform_unsupported "This Plugin supports native Windows 11 x64 only"
  exit /b 1
)
if "%SCORACE_VER_BUILD_NUMBER%"=="0" (
  call :set_error platform_unsupported "This Plugin supports native Windows 11 x64 only"
  exit /b 1
)
if "%SCORACE_VER_MAJOR%"=="10" if %SCORACE_VER_BUILD_NUMBER% LSS 22000 (
  call :set_error platform_unsupported "This Plugin supports native Windows 11 x64 only"
  exit /b 1
)
exit /b 0

:validate_projection
call :expect "%P_SCHEMA%" "scorace-runtime-lock/windows-cmd/v1" "Windows runtime lock projection schema is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_PLUGIN_ID%" "scorace-learning" "Runtime lock does not match Plugin identity" runtime_lock_invalid || exit /b 1
call :expect "%P_PROGRAM%" "scorace" "Runtime program identity is invalid" runtime_lock_invalid || exit /b 1
set "SCORACE_PROGRAM_VERSION=%P_PROGRAM_VERSION%"
call :assert_semver "%P_PROGRAM_VERSION%"
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime program identity is invalid" & if errorlevel 1 exit /b 1
call :expect "%P_CLI_CONTRACT%" "scorace-cli/v2" "Runtime CLI or learning API contract is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_LEARNING_API%" "scorace-learning-api/v2" "Runtime CLI or learning API contract is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_STATE_CONTRACT%" "scorace-study-state/v2" "Runtime state compatibility is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_STATE_LEGACY_READ%" "scorace-study-state/v1" "Runtime state compatibility is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_STATE_WRITE_POLICY%" "baseline-preserving" "Runtime state compatibility is invalid" runtime_lock_invalid || exit /b 1
call :assert_hex "%P_LOCK_SHA256%" 64
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime lock digest is invalid" & if errorlevel 1 exit /b 1
call :assert_hex "%P_SOURCE_REVISION%" 40
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime source identity is invalid" & if errorlevel 1 exit /b 1
call :assert_hex "%P_SOURCE_TREE_SHA256%" 64
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime source identity is invalid" & if errorlevel 1 exit /b 1
call :expect "%P_FEATURE_STUDY%" "true" "Runtime feature contract is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_FEATURE_READ_SOURCE%" "false" "Runtime feature contract is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_FEATURE_STDIO_MCP%" "false" "Runtime feature contract is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_TARGET_OS%" "windows" "Runtime target is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_TARGET_ARCH%" "x64" "Runtime target is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_TARGET_OS_MAJOR_MIN%" "11" "Runtime target is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_TARGET_OS_MAJOR_MAX%" "11" "Runtime target is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_SYSTEM_TRUST_KIND%" "unsigned" "Windows runtime trust policy must be explicitly unsigned" runtime_lock_invalid || exit /b 1
set "SCORACE_ENCODED_VERSION=%P_PROGRAM_VERSION%"
set "SCORACE_URL_PERCENT=%%"
for /f "tokens=1,* delims=+" %%A in ("%P_PROGRAM_VERSION%") do if not "%%B"=="" set "SCORACE_ENCODED_VERSION=%%A%SCORACE_URL_PERCENT%2B%%B"
set "SCORACE_EXPECTED_ARCHIVE_URL=https://github.com/scoracecom/plugins/releases/download/scorace-v%SCORACE_ENCODED_VERSION%/scorace-%SCORACE_ENCODED_VERSION%-windows-x64.zip"
call :expect "%P_ARCHIVE_URL%" "%SCORACE_EXPECTED_ARCHIVE_URL%" "Runtime archive URL is not the fixed ScorAce release URL" runtime_lock_invalid || exit /b 1
call :assert_hex "%P_ARCHIVE_SHA256%" 64
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime archive identity is invalid" & if errorlevel 1 exit /b 1
call :assert_positive_integer "%P_ARCHIVE_BYTES%"
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime archive identity is invalid" & if errorlevel 1 exit /b 1
call :expect "%P_ARCHIVE_FORMAT%" "zip" "Runtime archive identity is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_ARCHIVE_ROOT%" "scorace-%P_PROGRAM_VERSION%-windows-x64" "Runtime archive root is invalid" runtime_lock_invalid || exit /b 1
call :expect "%P_EXECUTABLE_PATH%" "bin/scorace.exe" "Runtime executable identity is invalid" runtime_lock_invalid || exit /b 1
call :assert_hex "%P_EXECUTABLE_SHA256%" 64
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime executable identity is invalid" & if errorlevel 1 exit /b 1
call :assert_positive_integer "%P_EXECUTABLE_BYTES%"
if errorlevel 1 call :set_error runtime_lock_invalid "Runtime executable identity is invalid" & if errorlevel 1 exit /b 1
set "SCORACE_EXECUTABLE_ENTRY="
set "SCORACE_RELEASE_ENTRY="
for /l %%I in (1,1,%SCORACE_PAYLOAD_COUNT%) do (
  call :validate_payload_entry %%I
  if errorlevel 1 (
    call :set_error runtime_lock_invalid "Runtime payload is invalid"
    exit /b 1
  )
)
if not defined SCORACE_EXECUTABLE_ENTRY (
  call :set_error runtime_lock_invalid "Runtime payload is incomplete"
  exit /b 1
)
if not defined SCORACE_RELEASE_ENTRY (
  call :set_error runtime_lock_invalid "Runtime payload is incomplete"
  exit /b 1
)
exit /b 0

:expect
if /i "%~1"=="%~2" exit /b 0
call :set_error "%~4" "%~3"
exit /b 1

:validate_payload_entry
set "SCORACE_ENTRY_PATH=!P_PAYLOAD_%~1_PATH!"
set "SCORACE_ENTRY_SHA256=!P_PAYLOAD_%~1_SHA256!"
set "SCORACE_ENTRY_BYTES=!P_PAYLOAD_%~1_BYTES!"
set "SCORACE_ENTRY_ROLE=!P_PAYLOAD_%~1_ROLE!"
if not defined SCORACE_ENTRY_PATH exit /b 1
if not defined SCORACE_ENTRY_SHA256 exit /b 1
if not defined SCORACE_ENTRY_BYTES exit /b 1
if not defined SCORACE_ENTRY_ROLE exit /b 1
call :assert_archive_path "%SCORACE_ENTRY_PATH%"
if errorlevel 1 exit /b 1
if "%SCORACE_ENTRY_PATH%"==".scorace/runtime-lock.json" exit /b 1
if /i not "%SCORACE_ENTRY_ROLE%"=="runtime" if /i not "%SCORACE_ENTRY_ROLE%"=="public_resource" if /i not "%SCORACE_ENTRY_ROLE%"=="license" if /i not "%SCORACE_ENTRY_ROLE%"=="metadata" exit /b 1
call :assert_hex "%SCORACE_ENTRY_SHA256%" 64
if errorlevel 1 exit /b 1
call :assert_positive_integer "%SCORACE_ENTRY_BYTES%"
if errorlevel 1 exit /b 1
set /a SCORACE_PREVIOUS=%~1-1
for /l %%J in (1,1,%SCORACE_PREVIOUS%) do if /i "%SCORACE_ENTRY_PATH%"=="!P_PAYLOAD_%%J_PATH!" exit /b 1
if "%SCORACE_ENTRY_PATH%"=="%P_EXECUTABLE_PATH%" (
  if not "%SCORACE_ENTRY_ROLE%"=="runtime" exit /b 1
  if not "%SCORACE_ENTRY_SHA256%"=="%P_EXECUTABLE_SHA256%" exit /b 1
  if not "%SCORACE_ENTRY_BYTES%"=="%P_EXECUTABLE_BYTES%" exit /b 1
  set "SCORACE_EXECUTABLE_ENTRY=1"
)
if "%SCORACE_ENTRY_PATH%"=="runtime-release.json" (
  if not "%SCORACE_ENTRY_ROLE%"=="metadata" exit /b 1
  set "SCORACE_RELEASE_ENTRY=1"
)
exit /b 0

:assert_semver
set "SCORACE_SEMVER=%~1"
if not defined SCORACE_SEMVER exit /b 1
for /f "delims=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-+" %%C in ("%SCORACE_SEMVER%") do exit /b 1
set "SCORACE_SEMVER_MAJOR="
set "SCORACE_SEMVER_MINOR="
set "SCORACE_SEMVER_PATCH="
set "SCORACE_SEMVER_EXTRA="
for /f "tokens=1-4 delims=." %%A in ("%SCORACE_SEMVER%") do (
  set "SCORACE_SEMVER_MAJOR=%%A"
  set "SCORACE_SEMVER_MINOR=%%B"
  set "SCORACE_SEMVER_PATCH=%%C"
  set "SCORACE_SEMVER_EXTRA=%%D"
)
call :assert_digits "%SCORACE_SEMVER_MAJOR%" || exit /b 1
call :assert_digits "%SCORACE_SEMVER_MINOR%" || exit /b 1
set "SCORACE_SEMVER_PATCH_CORE=%SCORACE_SEMVER_PATCH%"
for /f "tokens=1 delims=-+" %%A in ("%SCORACE_SEMVER_PATCH%") do set "SCORACE_SEMVER_PATCH_CORE=%%A"
call :assert_digits "%SCORACE_SEMVER_PATCH_CORE%" || exit /b 1
if defined SCORACE_SEMVER_EXTRA if "%SCORACE_SEMVER_PATCH%"=="%SCORACE_SEMVER_PATCH_CORE%" exit /b 1
if "%SCORACE_SEMVER:~-1%"=="-" exit /b 1
if "%SCORACE_SEMVER:~-1%"=="+" exit /b 1
exit /b 0

:assert_digits
set "SCORACE_DIGITS=%~1"
if not defined SCORACE_DIGITS exit /b 1
for /f "delims=0123456789" %%C in ("%SCORACE_DIGITS%") do exit /b 1
exit /b 0

:prepare_run_environment
if not defined SCORACE_SESSION_ID if defined CODEX_THREAD_ID set "SCORACE_SESSION_ID=%CODEX_THREAD_ID%"
if not defined SCORACE_SESSION_ID if defined CODEX_SESSION_ID set "SCORACE_SESSION_ID=%CODEX_SESSION_ID%"
set "SCORACE_METHOD_BASE=%CODEX_HOME%"
if not defined SCORACE_METHOD_BASE (
  if not defined USERPROFILE (
    call :set_error runtime_root_unavailable "USERPROFILE is unavailable"
    exit /b 1
  )
  set "SCORACE_METHOD_BASE=%USERPROFILE%\.codex"
)
set "SCORACE_METHOD_ROOT=%SCORACE_METHOD_BASE%\skills"
call :assert_absolute "%SCORACE_METHOD_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Method root must be absolute"
  exit /b 1
)
if not defined SCORACE_METHOD_ROOTS (
  set "SCORACE_JSON_METHOD_ROOT=%SCORACE_METHOD_ROOT:\=\\%"
  set "SCORACE_METHOD_ROOTS=["!SCORACE_JSON_METHOD_ROOT!"]"
  exit /b 0
)
set "SCORACE_ROOTS=%SCORACE_METHOD_ROOTS%"
if not "%SCORACE_ROOTS:~0,1%"=="[" if not "%SCORACE_ROOTS:~-1%"=="]" (
  call :set_error invalid_input "SCORACE_METHOD_ROOTS must be a JSON array"
  exit /b 1
)
if not "%SCORACE_ROOTS:~0,1%"=="[" (
  call :set_error invalid_input "SCORACE_METHOD_ROOTS must be a JSON array"
  exit /b 1
)
if not "%SCORACE_ROOTS:~-1%"=="]" (
  call :set_error invalid_input "SCORACE_METHOD_ROOTS must be a JSON array"
  exit /b 1
)
set "SCORACE_ROOTS=%SCORACE_ROOTS:~1,-1%"
set "SCORACE_JSON_METHOD_ROOT=%SCORACE_METHOD_ROOT:\=\\%"
if defined SCORACE_ROOTS (
  set "SCORACE_METHOD_ROOTS=[!SCORACE_ROOTS!,"!SCORACE_JSON_METHOD_ROOT!"]"
) else set "SCORACE_METHOD_ROOTS=["!SCORACE_JSON_METHOD_ROOT!"]"
exit /b 0
:acquire_install_lock
set "SCORACE_INSTALL_LOCK=%SCORACE_RUNTIME_ROOT%\.install.lock"
set "SCORACE_LOCK_ATTEMPT=0"
:acquire_install_lock_try
2>nul mkdir "%SCORACE_INSTALL_LOCK%"
if not errorlevel 1 (
  set "SCORACE_LOCK_OWNED=1"
  >"%SCORACE_INSTALL_LOCK%\owner" echo token:%RANDOM%%RANDOM%
  if errorlevel 1 (
    rmdir /s /q "%SCORACE_INSTALL_LOCK%" >nul 2>&1
    set "SCORACE_LOCK_OWNED=0"
    call :set_error runtime_root_unavailable "Managed install lock cannot be created"
    exit /b 1
  )
  exit /b 0
)
if exist "%SCORACE_INSTALL_LOCK%" if not exist "%SCORACE_INSTALL_LOCK%\*" (
  call :set_error runtime_root_unavailable "Managed install lock must be a directory"
  exit /b 1
)
set /a SCORACE_LOCK_ATTEMPT+=1
if %SCORACE_LOCK_ATTEMPT% GEQ 120 (
  call :set_error install_busy "Another runtime installation is still in progress"
  exit /b 1
)
"%SCORACE_TIMEOUT%" /t 1 /nobreak >nul 2>&1
goto :acquire_install_lock_try

:ensure_runtime_root
call :assert_no_reparse "%SCORACE_RUNTIME_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime path contains a reparse point"
  exit /b 1
)
if exist "%SCORACE_RUNTIME_ROOT%" if not exist "%SCORACE_RUNTIME_ROOT%\*" (
  call :set_error runtime_root_unavailable "Managed runtime root is not a directory"
  exit /b 1
)
mkdir "%SCORACE_RUNTIME_ROOT%" >nul 2>&1
if errorlevel 1 if not exist "%SCORACE_RUNTIME_ROOT%\*" (
  call :set_error runtime_root_unavailable "Managed runtime root cannot be created"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_RUNTIME_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime path contains a reparse point"
  exit /b 1
)
exit /b 0

:new_stage
set "SCORACE_STAGE=%SCORACE_RUNTIME_ROOT%\.prepare-%SCORACE_PROGRAM_VERSION%-%RANDOM%-%RANDOM%"
if exist "%SCORACE_STAGE%" goto :new_stage
mkdir "%SCORACE_STAGE%" >nul 2>&1
if errorlevel 1 (
  call :set_error install_failed "Runtime staging directory cannot be created"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_STAGE%"
if errorlevel 1 (
  call :set_error install_failed "Runtime staging directory contains a reparse point"
  exit /b 1
)
exit /b 0

:verify_archive_file
if not exist "%~1" if not exist "%~1\*" (
  call :set_error archive_invalid "Runtime archive is missing"
  exit /b 1
)
if exist "%~1\*" (
  call :set_error archive_invalid "Runtime archive must be a regular file"
  exit /b 1
)
call :assert_no_reparse "%~1"
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive contains a reparse point"
  exit /b 1
)
call :file_size "%~1" SCORACE_ACTUAL_SIZE
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive is missing"
  exit /b 1
)
if not "%SCORACE_ACTUAL_SIZE%"=="%P_ARCHIVE_BYTES%" (
  call :set_error archive_invalid "Runtime archive size does not match the lock"
  exit /b 1
)
call :hash_file "%~1" SCORACE_ACTUAL_SHA
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive digest could not be read"
  exit /b 1
)
if /i not "%SCORACE_ACTUAL_SHA%"=="%P_ARCHIVE_SHA256%" (
  call :set_error archive_invalid "Runtime archive digest does not match the lock"
  exit /b 1
)
exit /b 0

:validate_archive_entries
set "SCORACE_ARCHIVE_LIST=%SCORACE_STAGE%\archive-list.txt"
"%SCORACE_TAR%" -tf "%SCORACE_ARCHIVE_COPY%" >"%SCORACE_ARCHIVE_LIST%" 2>nul
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive is not a readable ZIP"
  exit /b 1
)
set "SCORACE_ARCHIVE_ENTRY_COUNT=0"
set "SCORACE_ARCHIVE_ROOT_SEEN=0"
set "SCORACE_ARCHIVE_DESCENDANT_SEEN=0"
set "SCORACE_ARCHIVE_ERROR="
for /f "usebackq delims=" %%E in ("%SCORACE_ARCHIVE_LIST%") do (
  set "SCORACE_ARCHIVE_ENTRY=%%E"
  call :validate_archive_entry
  if errorlevel 1 set "SCORACE_ARCHIVE_ERROR=1"
)
if defined SCORACE_ARCHIVE_ERROR exit /b 1
if "%SCORACE_ARCHIVE_ROOT_SEEN%"=="0" if "%SCORACE_ARCHIVE_DESCENDANT_SEEN%"=="0" (
  call :set_error archive_invalid "Runtime archive is missing its declared root directory"
  exit /b 1
)
if "%SCORACE_ARCHIVE_DESCENDANT_SEEN%"=="0" (
  call :set_error archive_invalid "Runtime archive has no payload entries"
  exit /b 1
)
set "SCORACE_ARCHIVE_TYPES=%SCORACE_STAGE%\archive-types.txt"
"%SCORACE_TAR%" -tvf "%SCORACE_ARCHIVE_COPY%" >"%SCORACE_ARCHIVE_TYPES%" 2>nul
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive metadata is not readable"
  exit /b 1
)
for /f "usebackq tokens=1" %%T in ("%SCORACE_ARCHIVE_TYPES%") do (
  set "SCORACE_ARCHIVE_TYPE=%%T"
  if not "!SCORACE_ARCHIVE_TYPE:~0,1!"=="-" if not "!SCORACE_ARCHIVE_TYPE:~0,1!"=="d" set "SCORACE_ARCHIVE_ERROR=1"
)
if defined SCORACE_ARCHIVE_ERROR (
  call :set_error archive_invalid "Runtime archive contains a non-regular or non-directory entry"
  exit /b 1
)
exit /b 0

:validate_archive_entry
set "SCORACE_ENTRY=%SCORACE_ARCHIVE_ENTRY%"
if not defined SCORACE_ENTRY exit /b 1
set "SCORACE_ENTRY_IS_DIRECTORY=0"
if "!SCORACE_ENTRY:~-1!"=="/" (
  set "SCORACE_ENTRY_IS_DIRECTORY=1"
  set "SCORACE_ENTRY=!SCORACE_ENTRY:~0,-1!"
)
call :assert_archive_path "%SCORACE_ENTRY%"
if errorlevel 1 exit /b 1
for /f "tokens=1 delims=/" %%F in ("%SCORACE_ENTRY%") do if /i not "%%F"=="%P_ARCHIVE_ROOT%" exit /b 1
if /i "%SCORACE_ENTRY%"=="%P_ARCHIVE_ROOT%" (
  if "%SCORACE_ENTRY_IS_DIRECTORY%"=="0" exit /b 1
  set "SCORACE_ARCHIVE_ROOT_SEEN=1"
) else set "SCORACE_ARCHIVE_DESCENDANT_SEEN=1"
set /a SCORACE_ARCHIVE_ENTRY_COUNT+=1
set /a SCORACE_ARCHIVE_PREVIOUS=SCORACE_ARCHIVE_ENTRY_COUNT-1
for /l %%J in (1,1,%SCORACE_ARCHIVE_PREVIOUS%) do if /i "%SCORACE_ENTRY%"=="!SCORACE_ARCHIVE_ENTRY_%%J!" exit /b 1
set "SCORACE_ARCHIVE_ENTRY_%SCORACE_ARCHIVE_ENTRY_COUNT%=%SCORACE_ENTRY%"
exit /b 0

:extract_archive
set "SCORACE_EXTRACTION=%SCORACE_STAGE%\extracted"
mkdir "%SCORACE_EXTRACTION%" >nul 2>&1
if errorlevel 1 (
  call :set_error install_failed "Runtime archive staging directory cannot be created"
  exit /b 1
)
"%SCORACE_TAR%" -xf "%SCORACE_ARCHIVE_COPY%" -C "%SCORACE_EXTRACTION%" >nul 2>&1
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive extraction failed"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_EXTRACTION%"
if errorlevel 1 (
  call :set_error archive_invalid "Runtime archive contains a reparse point"
  exit /b 1
)
set "SCORACE_CANDIDATE=%SCORACE_EXTRACTION%\%P_ARCHIVE_ROOT%"
if not exist "%SCORACE_CANDIDATE%\*" (
  call :set_error archive_invalid "Runtime archive root is missing"
  exit /b 1
)
for /f "delims=" %%T in ('dir /b /a "%SCORACE_EXTRACTION%" 2^>nul') do if /i not "%%T"=="%P_ARCHIVE_ROOT%" (
  call :set_error archive_invalid "Runtime archive contains an unexpected top-level entry"
  exit /b 1
)
exit /b 0

:publish_candidate
set "SCORACE_VERSION_ROOT=%SCORACE_RUNTIME_ROOT%\%SCORACE_PROGRAM_VERSION%"
call :assert_no_reparse "%SCORACE_VERSION_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime path contains a reparse point"
  exit /b 1
)
if exist "%SCORACE_VERSION_ROOT%" if not exist "%SCORACE_VERSION_ROOT%\*" (
  call :set_error runtime_root_unavailable "Managed runtime version path is not a directory"
  exit /b 1
)
mkdir "%SCORACE_VERSION_ROOT%" >nul 2>&1
if errorlevel 1 if not exist "%SCORACE_VERSION_ROOT%\*" (
  call :set_error install_failed "Managed runtime version path cannot be created"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_VERSION_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime path contains a reparse point"
  exit /b 1
)
set "SCORACE_TARGET_ROOT=%SCORACE_VERSION_ROOT%\windows-x64"
if exist "%SCORACE_TARGET_ROOT%" if not exist "%SCORACE_TARGET_ROOT%\*" (
  call :set_error install_failed "Existing runtime path is not a directory"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_TARGET_ROOT%"
if errorlevel 1 (
  call :set_error install_failed "Existing runtime path contains a reparse point"
  exit /b 1
)
set "SCORACE_BACKUP="
set "SCORACE_OLD_MOVED=0"
set "SCORACE_PUBLISHED=0"
if exist "%SCORACE_TARGET_ROOT%\*" (
  set "SCORACE_BACKUP=%SCORACE_VERSION_ROOT%\.previous-windows-x64-%RANDOM%-%RANDOM%"
  move /y "%SCORACE_TARGET_ROOT%" "!SCORACE_BACKUP!" >nul 2>&1
  if errorlevel 1 (
    call :set_error install_failed "Existing runtime could not be backed up"
    exit /b 1
  )
  set "SCORACE_OLD_MOVED=1"
)
move /y "%SCORACE_CANDIDATE%" "%SCORACE_TARGET_ROOT%" >nul 2>&1
if errorlevel 1 (
  if "%SCORACE_OLD_MOVED%"=="1" move /y "!SCORACE_BACKUP!" "%SCORACE_TARGET_ROOT%" >nul 2>&1
  if "%SCORACE_OLD_MOVED%"=="1" if not exist "%SCORACE_TARGET_ROOT%\*" (
    call :set_error install_failed "Runtime publish failed and the previous runtime could not be restored"
    exit /b 1
  )
  call :set_error install_failed "Runtime could not be published"
  exit /b 1
)
set "SCORACE_PUBLISHED=1"
if "%SCORACE_OLD_MOVED%"=="1" rmdir /s /q "!SCORACE_BACKUP!" >nul 2>&1
set "SCORACE_EXECUTABLE=%SCORACE_TARGET_ROOT%\%P_EXECUTABLE_PATH:/=\%"
exit /b 0

:validate_installed
set "SCORACE_TARGET_ROOT=%SCORACE_RUNTIME_ROOT%\%SCORACE_PROGRAM_VERSION%\windows-x64"
call :assert_no_reparse "%SCORACE_TARGET_ROOT%"
if errorlevel 1 (
  call :set_error runtime_root_unavailable "Managed runtime path contains a reparse point"
  exit /b 1
)
if not exist "%SCORACE_TARGET_ROOT%\*" (
  call :set_error dependency_missing "The locked scorace runtime is not installed"
  exit /b 1
)
set "SCORACE_FAILURE_CODE=runtime_integrity_mismatch"
call :verify_payload_tree "%SCORACE_TARGET_ROOT%" runtime_integrity_mismatch
if errorlevel 1 exit /b 1
set "SCORACE_EXECUTABLE=%SCORACE_TARGET_ROOT%\%P_EXECUTABLE_PATH:/=\%"
set "SCORACE_ENTRY_PATH=%P_EXECUTABLE_PATH%"
set "SCORACE_ENTRY_SHA256=%P_EXECUTABLE_SHA256%"
set "SCORACE_ENTRY_BYTES=%P_EXECUTABLE_BYTES%"
call :verify_one_file
if errorlevel 1 exit /b 1
call :verify_version "%SCORACE_EXECUTABLE%"
if errorlevel 1 exit /b 1
exit /b 0

:verify_payload_tree
set "SCORACE_VERIFY_BASE=%~1"
set "SCORACE_FAILURE_CODE=%~2"
if not exist "%SCORACE_VERIFY_BASE%\*" (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime root is missing"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_VERIFY_BASE%"
if errorlevel 1 (
  call :set_error archive_invalid "Runtime tree contains a reparse point"
  exit /b 1
)
for /l %%I in (1,1,%SCORACE_PAYLOAD_COUNT%) do (
  set "SCORACE_ENTRY_PATH=!P_PAYLOAD_%%I_PATH!"
  set "SCORACE_ENTRY_SHA256=!P_PAYLOAD_%%I_SHA256!"
  set "SCORACE_ENTRY_BYTES=!P_PAYLOAD_%%I_BYTES!"
  call :verify_one_file
  if errorlevel 1 exit /b 1
)
set "SCORACE_TREE_ERROR="
for /f "delims=" %%F in ('dir /a-d /s /b "%SCORACE_VERIFY_BASE%" 2^>nul') do (
  set "SCORACE_ACTUAL_REL=%%F"
  set "SCORACE_ACTUAL_REL=!SCORACE_ACTUAL_REL:%SCORACE_VERIFY_BASE%\=!"
  set "SCORACE_ACTUAL_REL=!SCORACE_ACTUAL_REL:\=/!"
  call :payload_contains "!SCORACE_ACTUAL_REL!"
  if errorlevel 1 set "SCORACE_TREE_ERROR=1"
)
if defined SCORACE_TREE_ERROR (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime directory contains an unlisted file"
  exit /b 1
)
exit /b 0

:verify_one_file
set "SCORACE_VERIFY_PATH=%SCORACE_VERIFY_BASE%\%SCORACE_ENTRY_PATH:/=\%"
if not exist "%SCORACE_VERIFY_PATH%" (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime file is missing"
  exit /b 1
)
if exist "%SCORACE_VERIFY_PATH%\*" (
  call :set_error archive_invalid "Runtime payload entry is a directory"
  exit /b 1
)
call :file_size "%SCORACE_VERIFY_PATH%" SCORACE_ACTUAL_SIZE
if errorlevel 1 (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime file size could not be read"
  exit /b 1
)
if not "%SCORACE_ACTUAL_SIZE%"=="%SCORACE_ENTRY_BYTES%" (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime file size does not match the lock"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_VERIFY_PATH%"
if errorlevel 1 (
  call :set_error archive_invalid "Runtime payload contains a reparse point"
  exit /b 1
)
call :hash_file "%SCORACE_VERIFY_PATH%" SCORACE_ACTUAL_SHA
if errorlevel 1 (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime file digest could not be read"
  exit /b 1
)
if /i not "%SCORACE_ACTUAL_SHA%"=="%SCORACE_ENTRY_SHA256%" (
  call :set_error "%SCORACE_FAILURE_CODE%" "Runtime file digest does not match the lock"
  exit /b 1
)
exit /b 0

:verify_version
rem ponytail: five bounded version-probe retries; extend only with a measured file-lock window.
set "SCORACE_VERSION_ATTEMPT=0"
:verify_version_try
call :verify_version_once "%~1"
if not errorlevel 1 exit /b 0
set /a SCORACE_VERSION_ATTEMPT+=1
if %SCORACE_VERSION_ATTEMPT% GEQ 5 (
  if "%SCORACE_VERSION_LINE_COUNT%"=="0" (
    call :set_error runtime_incompatible "Runtime version probe failed"
  ) else if "%SCORACE_VERSION_LINE_COUNT%"=="1" (
    call :set_error runtime_incompatible "Runtime version does not match the lock"
  ) else call :set_error runtime_incompatible "Runtime version probe returned invalid JSON"
  exit /b 1
)
"%SCORACE_TIMEOUT%" /t 1 /nobreak >nul 2>&1
goto :verify_version_try

:verify_version_once
set "SCORACE_VERSION_LINE_COUNT=0"
set "SCORACE_VERSION_LINE="
set "SCORACE_VERSION_PROBE_DIR=%SCORACE_STAGE%"
if not defined SCORACE_VERSION_PROBE_DIR set "SCORACE_VERSION_PROBE_DIR=%SCORACE_RUNTIME_ROOT%"
if not exist "%SCORACE_VERSION_PROBE_DIR%\*" (
  call :set_error runtime_root_unavailable "Runtime version probe directory is unavailable"
  exit /b 1
)
call :assert_no_reparse "%SCORACE_VERSION_PROBE_DIR%"
if errorlevel 1 exit /b 1
set "SCORACE_VERSION_TOKEN=%RANDOM%%RANDOM%"
set "SCORACE_VERSION_OUTPUT=%SCORACE_VERSION_PROBE_DIR%\.scorace-version-%SCORACE_VERSION_TOKEN%.out"
set "SCORACE_VERSION_EXPECTED=%SCORACE_VERSION_PROBE_DIR%\.scorace-version-%SCORACE_VERSION_TOKEN%.expected"
set "SCORACE_EXPECTED_VERSION_PREFIX={"status":"ok","operation":"runtime.version","schema":"scorace-runtime-version/v1","program":"scorace","program_version":"%P_PROGRAM_VERSION%","source_revision":"%P_SOURCE_REVISION%","source_tree_sha256":"%P_SOURCE_TREE_SHA256%","cli_contract":"scorace-cli/v2","learning_api":"scorace-learning-api/v2","state_compatibility":{"contract":"scorace-study-state/v2","legacy_read":["scorace-study-state/v1"],"
set "SCORACE_EXPECTED_VERSION_STATE="write_policy":"baseline-preserving"},"target":{"os":"windows","arch":"x64","os_major_min":11,"os_major_max":11},"features":{"study":true,"read_source":false,"stdio_mcp":false}}"
set "SCORACE_EXPECTED_VERSION_LINE=%SCORACE_EXPECTED_VERSION_PREFIX%%SCORACE_EXPECTED_VERSION_STATE%"
>"%SCORACE_VERSION_OUTPUT%" "%~1" version 2>nul
set "SCORACE_VERSION_COMMAND_STATUS=%ERRORLEVEL%"
for /f "usebackq delims=" %%L in ("%SCORACE_VERSION_OUTPUT%") do (
  set /a SCORACE_VERSION_LINE_COUNT+=1
  set "SCORACE_VERSION_LINE=%%L"
)
>"%SCORACE_VERSION_EXPECTED%" echo(!SCORACE_EXPECTED_VERSION_LINE!
"%SCORACE_FC%" "%SCORACE_VERSION_OUTPUT%" "%SCORACE_VERSION_EXPECTED%" >nul 2>&1
set "SCORACE_VERSION_MATCH_STATUS=%ERRORLEVEL%"
del /q "%SCORACE_VERSION_OUTPUT%" "%SCORACE_VERSION_EXPECTED%" >nul 2>&1
if not "%SCORACE_VERSION_LINE_COUNT%"=="1" exit /b 1
if not "%SCORACE_VERSION_MATCH_STATUS%"=="0" exit /b 1
exit /b 0

:cleanup
call :release_install_lock
if defined SCORACE_STAGE if exist "%SCORACE_STAGE%" rmdir /s /q "%SCORACE_STAGE%" >nul 2>&1
set "SCORACE_STAGE="
exit /b 0

:release_install_lock
if "%SCORACE_LOCK_OWNED%"=="1" rmdir /s /q "%SCORACE_INSTALL_LOCK%" >nul 2>&1
set "SCORACE_LOCK_OWNED=0"
exit /b 0

:file_size
set "SCORACE_FILE_SIZE="
for %%I in ("%~1") do set "SCORACE_FILE_SIZE=%%~zI"
if not defined SCORACE_FILE_SIZE exit /b 1
set "%~2=%SCORACE_FILE_SIZE%"
exit /b 0

:payload_contains
set "SCORACE_FOUND_PAYLOAD=0"
for /l %%I in (1,1,%SCORACE_PAYLOAD_COUNT%) do if /i "%~1"=="!P_PAYLOAD_%%I_PATH!" set "SCORACE_FOUND_PAYLOAD=1"
if "%SCORACE_FOUND_PAYLOAD%"=="1" exit /b 0
exit /b 1

:hash_file
rem ponytail: five bounded sharing retries; extend only with a measured AV lock window.
set "SCORACE_HASH_ATTEMPT=0"
:hash_file_try
set "SCORACE_HASH_RESULT="
for /f "skip=1 tokens=1" %%H in ('^"^"%SCORACE_CERTUTIL%^" -hashfile "%~1" SHA256 2^>nul^"') do if not defined SCORACE_HASH_RESULT set "SCORACE_HASH_RESULT=%%H"
if defined SCORACE_HASH_RESULT call :assert_hex "%SCORACE_HASH_RESULT%" 64
if errorlevel 1 set "SCORACE_HASH_RESULT="
if not defined SCORACE_HASH_RESULT (
  set /a SCORACE_HASH_ATTEMPT+=1
  if %SCORACE_HASH_ATTEMPT% GEQ 5 exit /b 1
  "%SCORACE_TIMEOUT%" /t 1 /nobreak >nul 2>&1
  goto :hash_file_try
)
set "%~2=%SCORACE_HASH_RESULT%"
exit /b 0

:assert_hex
set "SCORACE_HEX=%~1"
set "SCORACE_HEX_LENGTH=%~2"
if not defined SCORACE_HEX exit /b 1
for /f "delims=0123456789abcdefABCDEF" %%C in ("%SCORACE_HEX%") do exit /b 1
if "%SCORACE_HEX_LENGTH%"=="40" if not "%SCORACE_HEX:~39,1%"=="" if "%SCORACE_HEX:~40,1%"=="" goto :assert_hex_check
if "%SCORACE_HEX_LENGTH%"=="64" if not "%SCORACE_HEX:~63,1%"=="" if "%SCORACE_HEX:~64,1%"=="" goto :assert_hex_check
exit /b 1

:assert_hex_check
for /l %%I in (0,1,%SCORACE_HEX_LENGTH%-1) do (
  set "SCORACE_HEX_CHAR=!SCORACE_HEX:~%%I,1!"
  for /f "delims=0123456789abcdefABCDEF" %%C in ("!SCORACE_HEX_CHAR!") do exit /b 1
)
if "%SCORACE_HEX_LENGTH%"=="40" if /i "%SCORACE_HEX%"=="0000000000000000000000000000000000000000" exit /b 1
if "%SCORACE_HEX_LENGTH%"=="64" if /i "%SCORACE_HEX%"=="0000000000000000000000000000000000000000000000000000000000000000" exit /b 1
exit /b 0

:assert_positive_integer
set "SCORACE_INTEGER=%~1"
if not defined SCORACE_INTEGER exit /b 1
for /f "delims=0123456789" %%C in ("%SCORACE_INTEGER%") do exit /b 1
if "%SCORACE_INTEGER%"=="0" exit /b 1
exit /b 0

:assert_archive_path
set "SCORACE_SAFE_PATH=%~1"
if not defined SCORACE_SAFE_PATH exit /b 1
for /f "delims=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-" %%C in ("%SCORACE_SAFE_PATH%") do exit /b 1
if not "%SCORACE_SAFE_PATH:\=%"=="%SCORACE_SAFE_PATH%" exit /b 1
if "%SCORACE_SAFE_PATH:~0,1%"=="/" exit /b 1
if "%SCORACE_SAFE_PATH:~0,2%"=="//" exit /b 1
if "%SCORACE_SAFE_PATH://=%" neq "%SCORACE_SAFE_PATH%" exit /b 1
if "%SCORACE_SAFE_PATH:../=%" neq "%SCORACE_SAFE_PATH%" exit /b 1
if "%SCORACE_SAFE_PATH:./=%" neq "%SCORACE_SAFE_PATH%" exit /b 1
if "%SCORACE_SAFE_PATH:/..=%" neq "%SCORACE_SAFE_PATH%" exit /b 1
if "%SCORACE_SAFE_PATH:/.=%" neq "%SCORACE_SAFE_PATH%" exit /b 1
if "%SCORACE_SAFE_PATH%"=="." exit /b 1
if "%SCORACE_SAFE_PATH%"==".." exit /b 1
exit /b 0

:assert_no_reparse
set "SCORACE_CHECK_PATH=%~1"
if not defined SCORACE_CHECK_PATH exit /b 1
for %%I in ("%SCORACE_CHECK_PATH%") do set "SCORACE_CHECK_PATH=%%~fI"
if exist "%SCORACE_CHECK_PATH%" for /f "delims=" %%L in ('dir /aL /s /b "%SCORACE_CHECK_PATH%" 2^>nul') do exit /b 1
:assert_no_reparse_ancestor
for %%I in ("%SCORACE_CHECK_PATH%\..") do set "SCORACE_PARENT_PATH=%%~fI"
for %%I in ("%SCORACE_CHECK_PATH%") do set "SCORACE_CHECK_NAME=%%~nxI"
for /f "delims=" %%L in ('dir /aL /b "%SCORACE_PARENT_PATH%" 2^>nul') do if /i "%%~nxL"=="%SCORACE_CHECK_NAME%" exit /b 1
if /i "%SCORACE_PARENT_PATH%"=="%SCORACE_CHECK_PATH%" exit /b 0
set "SCORACE_CHECK_PATH=%SCORACE_PARENT_PATH%"
goto :assert_no_reparse_ancestor
exit /b 0

:assert_absolute
set "SCORACE_ABSOLUTE=%~1"
if not defined SCORACE_ABSOLUTE exit /b 1
if "%SCORACE_ABSOLUTE:~1,1%"==":" if "%SCORACE_ABSOLUTE:~2,1%"=="\" exit /b 0
if "%SCORACE_ABSOLUTE:~0,2%"=="\\" exit /b 0
exit /b 1

:reject_bang_path
setlocal DisableDelayedExpansion
set "SCORACE_BANG_PATH=%SCORACE_BANG_PATH_INPUT%"
if not defined SCORACE_BANG_PATH endlocal & exit /b 0
if "%SCORACE_BANG_PATH:!=%"=="%SCORACE_BANG_PATH%" goto :reject_bang_path_ok
endlocal & exit /b 1
:reject_bang_path_ok
endlocal & exit /b 0

:set_error
set "SCORACE_ERROR_CODE=%~1"
set "SCORACE_ERROR_SUMMARY=%~2"
exit /b 1
