[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string] $Command,
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]] $RemainingArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch { }
$script:TargetKey = "windows-x64"
$script:ProgramVersion = "unknown"
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:InstallLock = $null
$script:InstallLockHandle = $null
$script:InstallToken = [Guid]::NewGuid().ToString("N")
$script:Stage = $null
if ($null -eq $RemainingArguments) {
  $RemainingArguments = [string[]] @()
} else {
  $RemainingArguments = [string[]] @($RemainingArguments)
}

function Fail([string] $Code, [string] $Message) {
  $error = [System.Exception]::new($Message)
  $error.Data["ScoraceCode"] = $Code
  throw $error
}

function Get-Property($Object, [string] $Name) {
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Read-Json([string] $Path, [string] $Label, [string] $Code = "runtime_lock_invalid") {
  try {
    $text = [System.IO.File]::ReadAllText($Path)
    return @{ Value = ($text | ConvertFrom-Json); Text = $text }
  } catch {
    Fail $Code "$Label is missing or invalid"
  }
}

function Assert-RegularFile([string] $Path, [string] $Label, [string] $Code = "plugin_incomplete") {
  try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
  catch { Fail $Code "$Label is missing" }
  if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
    Fail $Code "$Label must be a regular file"
  }
  return $item
}

function Assert-NoReparsePath([string] $Path, [string] $Code = "runtime_root_unavailable") {
  if (-not [System.IO.Path]::IsPathRooted($Path)) { Fail $Code "Managed runtime path must be absolute" }
  $current = [System.IO.Path]::GetFullPath($Path)
  while ($true) {
    try {
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail $Code "Managed runtime path contains a reparse point"
      }
    } catch {
      if ($_.Exception.Data["ScoraceCode"]) { throw }
      if ($_.Exception -isnot [System.Management.Automation.ItemNotFoundException]) { throw }
    }
    $parent = [System.IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
    $current = $parent
  }
}

function Get-Paths {
  $script:ScriptDir = Split-Path -Parent $script:ScriptPath
  $script:PluginRoot = Split-Path -Parent $script:ScriptDir
  $script:ManifestPath = Join-Path $script:PluginRoot ".codex-plugin/plugin.json"
  $script:LockPath = Join-Path $script:PluginRoot ".scorace/runtime-lock.json"
  $script:LocalAppData = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($script:LocalAppData)) { $script:LocalAppData = $env:USERPROFILE }
  if ([string]::IsNullOrWhiteSpace($script:LocalAppData)) { Fail "runtime_root_unavailable" "LOCALAPPDATA is unavailable" }
  $rawRuntimeRoot = if ([string]::IsNullOrWhiteSpace($env:SCORACE_RUNTIME_ROOT)) {
    Join-Path $script:LocalAppData "ScorAce/runtime/scorace"
  } else { $env:SCORACE_RUNTIME_ROOT }
  if (-not [System.IO.Path]::IsPathRooted($rawRuntimeRoot)) { Fail "runtime_root_unavailable" "SCORACE_RUNTIME_ROOT must be absolute" }
  $script:RuntimeRoot = [System.IO.Path]::GetFullPath($rawRuntimeRoot)
}

function Check-Plugin {
  Assert-RegularFile $script:ManifestPath "Plugin manifest" | Out-Null
  Assert-RegularFile $script:LockPath "Runtime lock" | Out-Null
  Assert-RegularFile (Join-Path $script:ScriptDir "scorace-runtime.ps1") "Windows runtime helper" | Out-Null
  Assert-RegularFile (Join-Path $script:PluginRoot "tools/scorace-runtime.sh") "macOS runtime helper" | Out-Null
  foreach ($path in @("learning-release.json", "README.md", "LICENSE", "THIRD_PARTY_NOTICES.md")) {
    Assert-RegularFile (Join-Path $script:PluginRoot $path) "Plugin $path" | Out-Null
  }
  foreach ($item in @(Get-ChildItem -LiteralPath $script:PluginRoot -Force -Recurse -ErrorAction Stop)) {
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "plugin_incomplete" "Public Plugin contains a reparse point" }
    if (-not $item.PSIsContainer -and $item.Name -match "\.(c?js|mjs|ts|map)$") {
      Fail "plugin_incomplete" "Public Plugin contains a protected source-like file"
    }
  }
  foreach ($path in @("lib", "skills/scorace-study/scripts", "tools/study-assets.mjs", "tools/study-methods.mjs", "tools/teaching-renderer.mjs", "tools/interactive-demo.mjs", "tools/demo-cli.mjs", "tools/network-browser.mjs")) {
    $candidate = Join-Path $script:PluginRoot $path
    if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) { Fail "plugin_incomplete" "Public Plugin contains a protected or legacy path" }
  }
}

function Validate-Platform {
  if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { Fail "platform_unsupported" "This Plugin supports native Windows 11 x64 only" }
  $architecture = $env:PROCESSOR_ARCHITEW6432
  if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
  if ($architecture -ne "AMD64") { Fail "platform_unsupported" "This Plugin supports native Windows 11 x64 only" }
  $version = [Environment]::OSVersion.Version
  if ($version.Major -ne 10 -or $version.Build -lt 22000) { Fail "platform_unsupported" "This Plugin supports native Windows 11 x64 only" }
}

function Is-Hex([string] $Value, [int] $Length) {
  return $Value -match "^[0-9a-f]{$Length}$" -and $Value -notmatch "^0+$"
}

function Is-PositiveInteger($Value) {
  return ([string] $Value) -match "^[1-9][0-9]*$"
}

function Is-SemVer([string] $Value) {
  return $Value -match "^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
}

function Is-SafeArchivePath([string] $Value) {
  if ([string]::IsNullOrEmpty($Value) -or $Value -match "[\\]" -or $Value.StartsWith("/") -or $Value -match "^[A-Za-z]:" -or $Value -notmatch "^[A-Za-z0-9._/-]+$") { return $false }
  foreach ($part in $Value.Split("/")) {
    if ([string]::IsNullOrEmpty($part) -or $part -eq "." -or $part -eq "..") { return $false }
  }
  return $true
}

function Get-Target($Lock, [string] $TargetKey) {
  return Get-Property (Get-Property $Lock "runtimes") $TargetKey
}

function Validate-PayloadEntries($Entries, [string] $Label, [string] $ExecutablePath, [bool] $AllowMetadata = $true, [bool] $RequireMetadata = $true) {
  $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $executable = $false
  $metadata = $false
  foreach ($entry in @($Entries)) {
    $path = [string] (Get-Property $entry "path")
    if (-not (Is-SafeArchivePath $path) -or $path -eq ".scorace/runtime-lock.json") { Fail "runtime_lock_invalid" "$Label contains an unsafe path" }
    if (-not $paths.Add($path)) { Fail "runtime_lock_invalid" "$Label contains a duplicate path" }
    $role = [string] (Get-Property $entry "role")
    if ($role -notin @("runtime", "public_resource", "license", "metadata")) { Fail "runtime_lock_invalid" "$Label contains an invalid role" }
    if (-not $AllowMetadata -and $role -eq "metadata") { Fail "runtime_lock_invalid" "$Label contains an invalid metadata role" }
    if (-not (Is-Hex ([string] (Get-Property $entry "sha256")) 64) -or -not (Is-PositiveInteger (Get-Property $entry "bytes"))) { Fail "runtime_lock_invalid" "$Label contains an invalid digest or size" }
    if ($path -eq $ExecutablePath -and $role -eq "runtime") { $executable = $true }
    if ($path -eq "runtime-release.json" -and $role -eq "metadata") { $metadata = $true }
  }
  if (-not $executable -or ($RequireMetadata -and -not $metadata)) { Fail "runtime_lock_invalid" "$Label is incomplete" }
}

function Validate-LockRuntime($Runtime, [string] $TargetKey) {
  if ($null -eq $Runtime) { Fail "runtime_lock_invalid" "Runtime target is missing: $TargetKey" }
  $target = Get-Property $Runtime "target"
  $expectedExecutable = if ($TargetKey -eq "windows-x64") { "bin/scorace.exe" } else { "bin/scorace" }
  $expectedTarget = if ($TargetKey -eq "windows-x64") {
    @{ os = "windows"; arch = "x64"; os_major_min = 11; os_major_max = 11 }
  } else {
    @{ os = "darwin"; arch = "arm64"; os_major_min = 26; os_major_max = 26 }
  }
  foreach ($field in @("os", "arch", "os_major_min", "os_major_max")) {
    if ((Get-Property $target $field) -ne $expectedTarget[$field]) { Fail "runtime_lock_invalid" "Runtime target is invalid: $TargetKey" }
  }
  $trust = Get-Property $Runtime "system_trust"
  if ($TargetKey -eq "windows-x64") {
    $hasTeamId = $null -ne $trust -and $null -ne $trust.PSObject.Properties["team_id"]
    if ((Get-Property $trust "kind") -ne "unsigned" -or $hasTeamId) { Fail "runtime_lock_invalid" "Windows runtime trust policy must be explicitly unsigned" }
  } else {
    $team = [string] (Get-Property $trust "team_id")
    if ((Get-Property $trust "kind") -ne "apple_developer_id" -or $team -notmatch "^[A-Z0-9]{10}$") { Fail "runtime_lock_invalid" "macOS runtime trust policy is invalid" }
  }
  $archive = Get-Property $Runtime "archive"
  $expectedUrl = "https://github.com/scoracecom/plugins/releases/download/scorace-v$([Uri]::EscapeDataString($script:ProgramVersion))/scorace-$([Uri]::EscapeDataString($script:ProgramVersion))-$TargetKey.zip"
  if ((Get-Property $archive "url") -ne $expectedUrl -or (Get-Property $archive "format") -ne "zip" -or (Get-Property $archive "root") -ne "scorace-$($script:ProgramVersion)-$TargetKey" -or -not (Is-Hex ([string] (Get-Property $archive "sha256")) 64) -or -not (Is-PositiveInteger (Get-Property $archive "bytes"))) {
    Fail "runtime_lock_invalid" "Runtime archive identity is invalid: $TargetKey"
  }
  if ($TargetKey -eq "windows-x64") { $script:ArchiveRoot = [string] (Get-Property $archive "root") }
  $executable = Get-Property $Runtime "executable"
  if ((Get-Property $executable "path") -ne $expectedExecutable -or -not (Is-Hex ([string] (Get-Property $executable "sha256")) 64) -or -not (Is-PositiveInteger (Get-Property $executable "bytes"))) {
    Fail "runtime_lock_invalid" "Runtime executable identity is invalid: $TargetKey"
  }
  Validate-PayloadEntries (Get-Property $Runtime "payload") "Runtime payload $TargetKey" $expectedExecutable
  $executableEntry = @((Get-Property $Runtime "payload") | Where-Object { $_.path -eq $expectedExecutable })[0]
  if ((Get-Property $executableEntry "sha256") -ne (Get-Property $executable "sha256") -or (Get-Property $executableEntry "bytes") -ne (Get-Property $executable "bytes")) { Fail "runtime_lock_invalid" "Runtime executable payload does not match the lock: $TargetKey" }
}

function Validate-Lock($Lock, [string] $RawLock, $Manifest) {
  if ((Get-Property $Lock "schema") -ne "scorace-runtime-lock/v2") { Fail "runtime_lock_invalid" "Runtime lock schema is invalid" }
  if (([regex]::Matches($RawLock, '"darwin-arm64"\s*:')).Count -ne 1 -or ([regex]::Matches($RawLock, '"windows-x64"\s*:')).Count -ne 1) { Fail "runtime_lock_invalid" "Runtime lock contains duplicate or missing targets" }
  $manifestName = [string] (Get-Property $Manifest "name")
  $manifestVersion = [string] (Get-Property $Manifest "version")
  if ($manifestName -ne "scorace-learning" -or (Get-Property $Lock "plugin_id") -ne $manifestName -or (Get-Property $Lock "plugin_version") -ne $manifestVersion) { Fail "runtime_lock_invalid" "Runtime lock does not match Plugin identity" }
  $script:ProgramVersion = [string] (Get-Property $Lock "program_version")
  if ((Get-Property $Lock "program") -ne "scorace" -or -not (Is-SemVer $script:ProgramVersion)) { Fail "runtime_lock_invalid" "Runtime program identity is missing or invalid" }
  if ((Get-Property $Lock "cli_contract") -ne "scorace-cli/v2" -or (Get-Property $Lock "learning_api") -ne "scorace-learning-api/v2") { Fail "runtime_lock_invalid" "Runtime CLI or learning API contract is invalid" }
  $state = Get-Property $Lock "state_compatibility"
  if ((Get-Property $state "contract") -ne "scorace-study-state/v2" -or @((Get-Property $state "legacy_read"))[0] -ne "scorace-study-state/v1" -or (Get-Property $state "write_policy") -ne "baseline-preserving") { Fail "runtime_lock_invalid" "Runtime state compatibility is invalid" }
  if (-not (Is-Hex ([string] (Get-Property $Lock "source_revision")) 40) -or -not (Is-Hex ([string] (Get-Property $Lock "source_tree_sha256")) 64)) { Fail "runtime_lock_invalid" "Runtime source identity is missing or invalid" }
  $features = Get-Property $Lock "features"
  if ((Get-Property $features "study") -ne $true -or (Get-Property $features "read_source") -ne $false -or (Get-Property $features "stdio_mcp") -ne $false) { Fail "runtime_lock_invalid" "Runtime feature contract is invalid" }
  $runtimes = Get-Property $Lock "runtimes"
  if ($null -eq $runtimes) { Fail "runtime_lock_invalid" "Runtime lock must contain exactly darwin-arm64 and windows-x64 targets" }
  $runtimeNames = @($runtimes.PSObject.Properties.Name | Sort-Object)
  if (($runtimeNames -join ",") -ne "darwin-arm64,windows-x64") { Fail "runtime_lock_invalid" "Runtime lock must contain exactly darwin-arm64 and windows-x64 targets" }
  Validate-LockRuntime (Get-Target $Lock "darwin-arm64") "darwin-arm64"
  Validate-LockRuntime (Get-Target $Lock "windows-x64") "windows-x64"
}

function Get-FileSha256([string] $Path, [string] $Label = "runtime file", [string] $FailureCode = "runtime_integrity_mismatch") {
  # ponytail: four bounded sharing retries; extend only with a measured AV lock window.
  $retryDelays = @(50, 100, 200, 400)
  for ($attempt = 0; $attempt -le $retryDelays.Count; $attempt += 1) {
    $stream = $null
    $hasher = $null
    try {
      $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
      $hasher = [System.Security.Cryptography.SHA256]::Create()
      $digest = $hasher.ComputeHash($stream)
      return ([System.BitConverter]::ToString($digest).Replace("-", "").ToLowerInvariant())
    }
    catch {
      $category = Get-ErrorCategory $_
      if ($category -notin @("sharing_violation", "lock_violation") -or $attempt -eq $retryDelays.Count) {
        Fail $FailureCode "Runtime file digest could not be read: $Label ($category)"
      }
      Start-Sleep -Milliseconds $retryDelays[$attempt]
    }
    finally {
      if ($null -ne $hasher) { $hasher.Dispose() }
      if ($null -ne $stream) { $stream.Dispose() }
    }
  }
}

function Get-ErrorCategory($ErrorRecord) {
  $exception = $ErrorRecord.Exception
  while ($null -ne $exception.InnerException) { $exception = $exception.InnerException }
  if ($exception -is [System.IO.IOException] -and $exception.HResult -eq -2147024864) { return "sharing_violation" }
  if ($exception -is [System.IO.IOException] -and $exception.HResult -eq -2147024863) { return "lock_violation" }
  if ($exception -is [System.IO.IOException] -and $exception.HResult -eq -2147024891) { return "access_denied" }
  return $exception.GetType().Name
}

function Assert-FileMatches([string] $Base, $Entry, [string] $MissingCode = "dependency_missing", [string] $MismatchCode = "runtime_integrity_mismatch") {
  $path = Join-Path $Base ([string] $Entry.path)
  try { $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop }
  catch { Fail $MissingCode "Runtime file is missing: $($Entry.path)" }
  if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { Fail "archive_invalid" "Runtime file is not a regular file: $($Entry.path)" }
  if ($item.Length -ne [int64] $Entry.bytes -or (Get-FileSha256 $path ([string] $Entry.path) $MismatchCode) -ne ([string] $Entry.sha256).ToLowerInvariant()) { Fail $MismatchCode "Runtime file digest or size does not match the lock: $($Entry.path)" }
}

function Get-RelativePath([string] $Base, [string] $Path) {
  $relative = $Path.Substring($Base.Length).TrimStart("\", "/")
  return $relative.Replace("\", "/")
}

function Verify-PayloadTree([string] $Base, $Runtime, [string] $MissingCode = "dependency_missing", [string] $MismatchCode = "runtime_integrity_mismatch") {
  try { $rootItem = Get-Item -LiteralPath $Base -Force -ErrorAction Stop }
  catch { Fail "dependency_missing" "Locked ScorAce runtime is not installed" }
  if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { Fail "archive_invalid" "Runtime root is not a regular directory" }
  $entries = @((Get-Property $Runtime "payload"))
  $expected = @{}
  foreach ($entry in $entries) { $expected[[string] $entry.path] = $entry; Assert-FileMatches $Base $entry $MissingCode $MismatchCode }
  $actual = @{}
  foreach ($item in @(Get-ChildItem -LiteralPath $Base -Force -Recurse -ErrorAction Stop)) {
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "archive_invalid" "Runtime tree contains a reparse point" }
    if ($item.PSIsContainer) { continue }
    $relative = Get-RelativePath $Base $item.FullName
    $actual[$relative] = $true
  }
  $expectedNames = @($expected.Keys | Sort-Object)
  $actualNames = @($actual.Keys | Sort-Object)
  if (($expectedNames -join "`n") -ne ($actualNames -join "`n")) { Fail $MismatchCode "Runtime directory contains an unlisted or missing file" }
}

function Read-Release([string] $Base) {
  $releasePath = Join-Path $Base "runtime-release.json"
  Assert-RegularFile $releasePath "Runtime release metadata" "runtime_integrity_mismatch" | Out-Null
  return Read-Json $releasePath "Runtime release metadata" "runtime_integrity_mismatch"
}

function Validate-Release($Release, $LockRuntime) {
  $value = $Release.Value
  if ((Get-Property $value "schema") -ne "scorace-runtime-release/v1" -or (Get-Property $value "program") -ne "scorace" -or (Get-Property $value "program_version") -ne $script:ProgramVersion -or (Get-Property $value "source_revision") -ne $script:LockSourceRevision -or (Get-Property $value "source_tree_sha256") -ne $script:LockTreeSha256 -or (Get-Property $value "cli_contract") -ne "scorace-cli/v2" -or (Get-Property $value "learning_api") -ne "scorace-learning-api/v2") {
    Fail "runtime_incompatible" "Runtime release metadata does not match the lock"
  }
  $target = Get-Property $LockRuntime "target"
  foreach ($field in @("os", "arch", "os_major_min", "os_major_max")) {
    if ((Get-Property (Get-Property $value "target") $field) -ne (Get-Property $target $field)) { Fail "runtime_incompatible" "Runtime release target does not match the lock" }
  }
  $state = Get-Property $value "state_compatibility"
  if ((Get-Property $state "contract") -ne "scorace-study-state/v2" -or @((Get-Property $state "legacy_read"))[0] -ne "scorace-study-state/v1" -or (Get-Property $state "write_policy") -ne "baseline-preserving") { Fail "runtime_incompatible" "Runtime release state compatibility does not match the lock" }
  $features = Get-Property $value "features"
  if ((Get-Property $features "study") -ne $true -or (Get-Property $features "read_source") -ne $false -or (Get-Property $features "stdio_mcp") -ne $false) { Fail "runtime_incompatible" "Runtime release features do not match the lock" }
  Validate-PayloadEntries (Get-Property $value "files") "Runtime release payload" "bin/scorace.exe" $false $false
  $releaseFiles = @{}
  foreach ($entry in @((Get-Property $value "files"))) { $releaseFiles[[string] $entry.path] = $entry }
  $lockFiles = @{}
  foreach ($entry in @((Get-Property $LockRuntime "payload"))) {
    if ($entry.path -ne "runtime-release.json") { $lockFiles[[string] $entry.path] = $entry }
  }
  if ((($releaseFiles.Keys | Sort-Object) -join "`n") -ne (($lockFiles.Keys | Sort-Object) -join "`n")) { Fail "runtime_incompatible" "Runtime release payload does not match the lock" }
  foreach ($path in $lockFiles.Keys) {
    if ((Get-Property $releaseFiles[$path] "sha256") -ne (Get-Property $lockFiles[$path] "sha256") -or (Get-Property $releaseFiles[$path] "bytes") -ne (Get-Property $lockFiles[$path] "bytes") -or (Get-Property $releaseFiles[$path] "role") -ne (Get-Property $lockFiles[$path] "role")) { Fail "runtime_incompatible" "Runtime release payload does not match the lock" }
  }
  $script:ReleaseValue = $value
}

function Verify-Version([string] $Executable) {
  try { $output = & $Executable version 2>$null; if ($LASTEXITCODE -ne 0) { throw "version probe failed" } }
  catch { Fail "runtime_incompatible" "Runtime version probe failed" }
  try { $version = (($output -join "`n") | ConvertFrom-Json) }
  catch { Fail "runtime_incompatible" "Runtime version probe returned invalid JSON" }
  $target = Get-Property $script:LockRuntime "target"
  if ((Get-Property $version "schema") -ne "scorace-runtime-version/v1" -or (Get-Property $version "program") -ne "scorace" -or (Get-Property $version "program_version") -ne $script:ProgramVersion -or (Get-Property $version "source_revision") -ne $script:LockSourceRevision -or (Get-Property $version "source_tree_sha256") -ne $script:LockTreeSha256 -or (Get-Property $version "cli_contract") -ne "scorace-cli/v2" -or (Get-Property $version "learning_api") -ne "scorace-learning-api/v2") { Fail "runtime_incompatible" "Runtime version does not match the lock" }
  foreach ($field in @("os", "arch", "os_major_min", "os_major_max")) {
    if ((Get-Property (Get-Property $version "target") $field) -ne (Get-Property $target $field)) { Fail "runtime_incompatible" "Runtime version target does not match the lock" }
  }
  $features = Get-Property $version "features"
  if ((Get-Property $features "study") -ne $true -or (Get-Property $features "read_source") -ne $false -or (Get-Property $features "stdio_mcp") -ne $false) { Fail "runtime_incompatible" "Runtime version features do not match the lock" }
}

function Validate-Installed([string] $VersionRoot) {
  $script:TargetRoot = Join-Path $VersionRoot $script:TargetKey
  Assert-NoReparsePath $script:TargetRoot
  if (-not (Test-Path -LiteralPath $script:TargetRoot -PathType Container)) { Fail "dependency_missing" "The locked scorace runtime is not installed" }
  $script:LockRuntime = Get-Target $script:Lock "windows-x64"
  Verify-PayloadTree $script:TargetRoot $script:LockRuntime
  $release = Read-Release $script:TargetRoot
  Validate-Release $release $script:LockRuntime
  $executable = Join-Path $script:TargetRoot "bin/scorace.exe"
  $executableEntry = @($script:LockRuntime.payload | Where-Object { $_.path -eq "bin/scorace.exe" })[0]
  Assert-FileMatches $script:TargetRoot $executableEntry
  Verify-Version $executable
}

function Validate-Common {
  Get-Paths
  Check-Plugin
  Validate-Platform
  $manifestResult = Read-Json $script:ManifestPath "Plugin manifest"
  $lockResult = Read-Json $script:LockPath "Runtime lock"
  $script:Manifest = $manifestResult.Value
  $script:Lock = $lockResult.Value
  $script:LockRaw = $lockResult.Text
  $script:LockSourceRevision = [string] (Get-Property $script:Lock "source_revision")
  $script:LockTreeSha256 = [string] (Get-Property $script:Lock "source_tree_sha256")
  Validate-Lock $script:Lock $script:LockRaw $script:Manifest
}

function Write-Result($Object) {
  [Console]::Out.WriteLine(($Object | ConvertTo-Json -Compress -Depth 8))
}

function Check-Runtime {
  Validate-Common
  Validate-Installed (Join-Path $script:RuntimeRoot $script:ProgramVersion)
  Write-Result ([ordered]@{ status = "ok"; operation = "runtime.check"; ready = $true; program = "scorace"; program_version = $script:ProgramVersion; target = "windows-x64"; executable = (Join-Path $script:TargetRoot "bin/scorace.exe") })
}

function Ensure-RuntimeRoot {
  Assert-NoReparsePath $script:RuntimeRoot
  if (Test-Path -LiteralPath $script:RuntimeRoot -PathType Leaf) { Fail "runtime_root_unavailable" "Managed runtime root is not a directory" }
  try { [System.IO.Directory]::CreateDirectory($script:RuntimeRoot) | Out-Null }
  catch { Fail "runtime_root_unavailable" "Managed runtime root cannot be created" }
  Assert-NoReparsePath $script:RuntimeRoot
}

function Assert-InstallLockFile {
  $item = Get-Item -LiteralPath $script:InstallLock -Force -ErrorAction SilentlyContinue
  if ($null -ne $item -and ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0))) {
    Fail "runtime_root_unavailable" "Managed install lock must be a regular file"
  }
  return $item
}

function Acquire-InstallLock {
  $script:InstallLock = Join-Path -Path $script:RuntimeRoot -ChildPath ".install.lock"
  Assert-NoReparsePath $script:RuntimeRoot
  Assert-InstallLockFile | Out-Null
  for ($attempt = 0; $attempt -lt 120; $attempt += 1) {
    $stream = $null
    try {
      $stream = [System.IO.FileStream]::new($script:InstallLock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
      Assert-InstallLockFile | Out-Null
      $bytes = [System.Text.Encoding]::UTF8.GetBytes("token:$($script:InstallToken)`n")
      $stream.SetLength(0)
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush($true)
      $stream.Position = 0
      $script:InstallLockHandle = $stream
      $stream = $null
      return
    } catch {
      if ($null -ne $stream) { $stream.Dispose() }
      if ($null -ne $_.Exception.Data["ScoraceCode"]) { throw }
      if ((Get-ErrorCategory $_) -ne "sharing_violation") {
        Fail "runtime_root_unavailable" "Managed install lock cannot be opened"
      }
      Assert-InstallLockFile | Out-Null
      if ($attempt -eq 119) { break }
      Start-Sleep -Seconds 1
    }
  }
  Fail "install_busy" "Another runtime installation is still in progress"
}

function Release-InstallLock {
  if ($null -ne $script:InstallLockHandle) {
    try {
      $script:InstallLockHandle.Dispose()
    } finally {
      $script:InstallLockHandle = $null
    }
  }
}

function New-Stage {
  $name = ".prepare-$($script:ProgramVersion)-$PID-$([Guid]::NewGuid().ToString('N'))"
  $script:Stage = Join-Path $script:RuntimeRoot $name
  try { [System.IO.Directory]::CreateDirectory($script:Stage) | Out-Null }
  catch { Fail "install_failed" "Runtime staging directory cannot be created" }
  Assert-NoReparsePath $script:Stage
}

function Move-ItemWithRetry([string] $Source, [string] $Destination) {
  $retryDelays = @(50, 100, 200, 400)
  for ($attempt = 0; $attempt -le $retryDelays.Count; $attempt += 1) {
    try {
      [System.IO.Directory]::Move($Source, $Destination)
      return
    } catch {
      if ((Get-ErrorCategory $_) -notin @("sharing_violation", "lock_violation") -or $attempt -eq $retryDelays.Count) { throw }
      Start-Sleep -Milliseconds $retryDelays[$attempt]
    }
  }
}

function Get-ZipEntries([string] $ArchivePath) {
  try { $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath) }
  catch { Fail "archive_invalid" "Runtime archive is not a readable ZIP" }
  try {
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $entries = @()
    foreach ($entry in $zip.Entries) {
      $name = $entry.FullName
      if (-not $seen.Add($name)) { Fail "archive_invalid" "Runtime archive contains a duplicate path" }
      $isDirectory = $name.EndsWith("/")
      $path = if ($isDirectory) { $name.Substring(0, $name.Length - 1) } else { $name }
      if ($path -ne $script:ArchiveRoot -and -not $path.StartsWith("$($script:ArchiveRoot)/")) { Fail "archive_invalid" "Runtime archive has an unexpected root" }
      if ($path -ne $script:ArchiveRoot -and -not (Is-SafeArchivePath $path)) { Fail "archive_invalid" "Runtime archive contains an unsafe path" }
      if ($path -eq $script:ArchiveRoot -and -not $isDirectory) { Fail "archive_invalid" "Runtime archive root entry is not a directory" }
      $attributes = [System.BitConverter]::ToUInt32([System.BitConverter]::GetBytes([int32] $entry.ExternalAttributes), 0)
      $attributeLabel = "entry '$name' attributes 0x{0:X8}" -f $attributes
      $unixType = ($attributes -shr 16) -band 0xF000
      if ($unixType -notin @(0, 0x4000, 0x8000)) { Fail "archive_invalid" "Runtime archive contains a symlink or special file ($attributeLabel)" }
      $dosAttributes = $attributes -band 0xFFFF
      if (($dosAttributes -band 0x400) -ne 0 -or ($dosAttributes -band 0x08) -ne 0 -or ($dosAttributes -band 0xFFFFFFC0) -ne 0) { Fail "archive_invalid" "Runtime archive contains unsupported Windows file attributes ($attributeLabel)" }
      $dosDirectory = ($dosAttributes -band 0x10) -ne 0
      if (($unixType -ne 0 -and (($unixType -eq 0x4000) -ne $isDirectory)) -or ($dosDirectory -and -not $isDirectory)) { Fail "archive_invalid" "Runtime archive metadata disagrees with entry type ($attributeLabel)" }
      $entries += $entry
    }
    if ($entries.Count -eq 0) { Fail "archive_invalid" "Runtime archive has no entries" }
    $hasDescendant = @($entries | Where-Object { $_.FullName -like "$($script:ArchiveRoot)/*" }).Count -gt 0
    if (-not $hasDescendant) { Fail "archive_invalid" "Runtime archive is missing its declared root directory" }
    return $true
  } finally { $zip.Dispose() }
}

function Extract-Zip([string] $ArchivePath, [string] $Destination) {
  Get-ZipEntries $ArchivePath | Out-Null
  try { $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath) }
  catch { Fail "archive_invalid" "Runtime archive is not a readable ZIP" }
  try {
    foreach ($entry in $zip.Entries) {
      $relative = $entry.FullName.Replace("/", "\")
      $destinationPath = Join-Path $Destination $relative
      $fullDestination = [System.IO.Path]::GetFullPath($destinationPath)
      $fullBase = [System.IO.Path]::GetFullPath($Destination).TrimEnd("\") + "\"
      if (-not $fullDestination.StartsWith($fullBase, [System.StringComparison]::OrdinalIgnoreCase)) { Fail "archive_invalid" "Runtime archive path escapes its staging directory" }
      if ($entry.FullName.EndsWith("/")) {
        [System.IO.Directory]::CreateDirectory($fullDestination) | Out-Null
        continue
      }
      $parent = [System.IO.Path]::GetDirectoryName($fullDestination)
      [System.IO.Directory]::CreateDirectory($parent) | Out-Null
      Assert-NoReparsePath $parent "archive_invalid"
      $input = $entry.Open()
      try {
        $output = [System.IO.FileStream]::new($fullDestination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $input.CopyTo($output) } finally { $output.Dispose() }
      } finally { $input.Dispose() }
    }
  } catch {
    if ($_.Exception.Data["ScoraceCode"]) { throw }
    Fail "archive_invalid" "Runtime archive extraction failed"
  } finally { $zip.Dispose() }
  $candidate = Join-Path $Destination $script:ArchiveRoot
  if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { Fail "archive_invalid" "Runtime archive root is missing" }
  Assert-NoReparsePath $candidate "archive_invalid"
  return $candidate
}

function Verify-Archive([string] $ArchivePath) {
  Assert-RegularFile $ArchivePath "Runtime archive" "archive_invalid" | Out-Null
  $archive = $script:LockRuntime.archive
  $item = Get-Item -LiteralPath $ArchivePath -Force
  if ($item.Length -ne [int64] $archive.bytes -or (Get-FileSha256 $ArchivePath "runtime archive" "archive_invalid") -ne ([string] $archive.sha256).ToLowerInvariant()) { Fail "archive_invalid" "Runtime archive digest or size does not match the lock" }
}

function Download-Archive([string] $Path) {
  try { Invoke-WebRequest -Uri $script:LockRuntime.archive.url -OutFile $Path -UseBasicParsing -ErrorAction Stop }
  catch { Fail "download_failed" "Runtime archive download failed" }
}

function Prepare-Runtime([string[]] $PrepareArguments) {
  $sourceMode = $null
  $archiveSource = $null
  if ($PrepareArguments.Count -eq 1 -and $PrepareArguments[0] -eq "--allow-download") { $sourceMode = "download" }
  elseif ($PrepareArguments.Count -eq 2 -and $PrepareArguments[0] -eq "--archive") {
    $archiveSource = $PrepareArguments[1]
    if (-not [System.IO.Path]::IsPathRooted($archiveSource)) { Fail "invalid_command" "prepare --archive requires one absolute ZIP path" }
    $sourceMode = "archive"
  } else { Fail "invalid_command" "prepare requires --allow-download or --archive" }

  Validate-Common
  $script:LockRuntime = Get-Target $script:Lock "windows-x64"
  Ensure-RuntimeRoot
  Acquire-InstallLock
  try {
    try {
      Validate-Installed (Join-Path $script:RuntimeRoot $script:ProgramVersion)
      Write-Result ([ordered]@{ status = "ok"; operation = "runtime.prepare"; ready = $true; result = "reused"; program = "scorace"; program_version = $script:ProgramVersion; target = "windows-x64"; executable = (Join-Path $script:TargetRoot "bin/scorace.exe") })
      return
    } catch { }
    New-Stage
    $archiveCopy = Join-Path $script:Stage "runtime.zip"
    if ($sourceMode -eq "download") { Download-Archive $archiveCopy }
    else {
      Assert-RegularFile $archiveSource "Runtime archive" "archive_invalid" | Out-Null
      try { Copy-Item -LiteralPath $archiveSource -Destination $archiveCopy -Force -ErrorAction Stop }
      catch { Fail "archive_invalid" "Runtime archive cannot be staged" }
    }
    Verify-Archive $archiveCopy
    $extraction = Join-Path $script:Stage "extracted"
    [System.IO.Directory]::CreateDirectory($extraction) | Out-Null
    $candidate = Extract-Zip $archiveCopy $extraction
    Verify-PayloadTree $candidate $script:LockRuntime "archive_invalid" "archive_invalid"
    $release = Read-Release $candidate
    Validate-Release $release $script:LockRuntime
    Verify-Version (Join-Path $candidate "bin/scorace.exe")

    $versionRoot = Join-Path $script:RuntimeRoot $script:ProgramVersion
    Assert-NoReparsePath $versionRoot
    [System.IO.Directory]::CreateDirectory($versionRoot) | Out-Null
    $target = Join-Path $versionRoot "windows-x64"
    $backup = $null
    $oldMoved = $false
    $published = $false
    $publishPhase = "existing runtime backup"
    try {
      if (Test-Path -LiteralPath $target) {
        Assert-NoReparsePath $target
        $backup = Join-Path $versionRoot ".previous-windows-x64-$PID-$([Guid]::NewGuid().ToString('N'))"
        Move-ItemWithRetry $target $backup
        $oldMoved = $true
      }
      $publishPhase = "new runtime publish"
      Move-ItemWithRetry $candidate $target
      $published = $true
      if ($null -ne $backup -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
    } catch {
      $publishError = $_
      $rollbackCategory = $null
      if ($published -and (Test-Path -LiteralPath $target)) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
      if ($oldMoved -and $null -ne $backup -and (Test-Path -LiteralPath $backup)) {
        try { Move-ItemWithRetry $backup $target }
        catch { $rollbackCategory = Get-ErrorCategory $_ }
      }
      $category = Get-ErrorCategory $publishError
      $rollback = if (-not $oldMoved) { "rollback=not_needed" } elseif ($null -eq $rollbackCategory) { "rollback=restored" } else { "rollback_failed=$rollbackCategory" }
      Fail "install_failed" "Runtime could not be published ($publishPhase; $category; $rollback)"
    }
    Write-Result ([ordered]@{ status = "ok"; operation = "runtime.prepare"; ready = $true; result = "installed"; program = "scorace"; program_version = $script:ProgramVersion; target = "windows-x64"; executable = (Join-Path $target "bin/scorace.exe") })
  } finally {
    if ($null -ne $script:Stage -and (Test-Path -LiteralPath $script:Stage)) { Remove-Item -LiteralPath $script:Stage -Recurse -Force -ErrorAction SilentlyContinue }
    Release-InstallLock
  }
}

function Run-Runtime([string[]] $RunArguments) {
  if ($RunArguments.Count -eq 0) { Fail "invalid_command" "run requires a scorace command" }
  Validate-Common
  $script:LockRuntime = Get-Target $script:Lock "windows-x64"
  Validate-Installed (Join-Path $script:RuntimeRoot $script:ProgramVersion)
  if ([string]::IsNullOrWhiteSpace($env:SCORACE_SESSION_ID)) {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) { $env:SCORACE_SESSION_ID = $env:CODEX_THREAD_ID }
    elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_SESSION_ID)) { $env:SCORACE_SESSION_ID = $env:CODEX_SESSION_ID }
  }
  $methodBase = $env:CODEX_HOME
  if ([string]::IsNullOrWhiteSpace($methodBase)) {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { Fail "runtime_root_unavailable" "USERPROFILE is unavailable" }
    $methodBase = Join-Path -Path $env:USERPROFILE -ChildPath ".codex"
  }
  $methodRoot = Join-Path -Path $methodBase -ChildPath "skills"
  $roots = [System.Collections.Generic.List[string]]::new()
  if (-not [string]::IsNullOrWhiteSpace($env:SCORACE_METHOD_ROOTS)) {
    $rawRoots = $env:SCORACE_METHOD_ROOTS.Trim()
    if (-not ($rawRoots.StartsWith("[") -and $rawRoots.EndsWith("]"))) { Fail "invalid_input" "SCORACE_METHOD_ROOTS must be a JSON array" }
    try { $rawRootValues = @($rawRoots | ConvertFrom-Json) }
    catch { Fail "invalid_input" "SCORACE_METHOD_ROOTS must be a JSON array" }
    foreach ($root in $rawRootValues) {
      if ($null -eq $root -or $root.GetType().Name -ne "String") { Fail "invalid_input" "SCORACE_METHOD_ROOTS must be a JSON array of paths" }
      [void] $roots.Add([string] $root)
    }
  }
  if (-not $roots.Contains($methodRoot)) { [void] $roots.Add($methodRoot) }
  $rootArray = $roots.ToArray()
  $env:SCORACE_METHOD_ROOTS = ConvertTo-Json -InputObject $rootArray -Compress
  $executable = Join-Path $script:TargetRoot "bin/scorace.exe"
  & $executable @RunArguments
  exit $LASTEXITCODE
}

try {
  switch ($Command) {
    "check" {
      if ($RemainingArguments.Count -ne 0) { Fail "invalid_command" "check takes no arguments" }
      Check-Runtime
    }
    "prepare" { Prepare-Runtime $RemainingArguments }
    "run" { Run-Runtime $RemainingArguments }
    default { Fail "invalid_command" "usage: scorace-runtime.ps1 check|prepare --allow-download|prepare --archive ZIP|run scorace-command" }
  }
} catch {
  $code = $_.Exception.Data["ScoraceCode"]
  if ([string]::IsNullOrWhiteSpace([string] $code)) { $code = "runtime_error" }
  $details = [ordered]@{ program = "scorace"; program_version = $script:ProgramVersion }
  [Console]::Error.WriteLine((([ordered]@{ status = "error"; code = $code; summary = $_.Exception.Message; details = $details }) | ConvertTo-Json -Compress -Depth 8))
  exit 1
}
