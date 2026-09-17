#!/bin/sh

set -u
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" 2>/dev/null && /bin/pwd -P) || exit 1
PLUGIN_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && /bin/pwd -P) || exit 1
MANIFEST_PATH="$PLUGIN_ROOT/.codex-plugin/plugin.json"
LOCK_PATH="$PLUGIN_ROOT/.scorace/runtime-lock.json"
RUNTIME_ROOT="${HOME:-}/Library/Application Support/ScorAce/runtime/scorace"
TARGET_KEY="darwin-arm64"
TARGET_PREFIX="runtimes.$TARGET_KEY"
PROGRAM_VERSION=
PUBLISHER_TEAM_ID=
ARCHIVE_URL=
ARCHIVE_SHA256=
ARCHIVE_BYTES=
ARCHIVE_ROOT=
EXECUTABLE_PATH="bin/scorace"
EXECUTABLE_SHA256=
EXECUTABLE_BYTES=
PAYLOAD_COUNT=0
TARGET_ROOT=
STAGE=
INSTALL_LOCK=
OWNS_LOCK=0
ERROR_CODE=
ERROR_SUMMARY=

json_escape() {
  printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]/ /g'
}

lock_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$LOCK_PATH" 2>/dev/null
}

target_lock_value() {
  lock_value "$TARGET_PREFIX.$1"
}

manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST_PATH" 2>/dev/null
}

fail() {
  ERROR_CODE=$1
  ERROR_SUMMARY=$2
  return 1
}

emit_error() {
  version=${PROGRAM_VERSION:-unknown}
  printf '{"status":"error","code":"%s","summary":"%s","details":{"program":"scorace","program_version":"%s"}}\n' \
    "$(json_escape "$ERROR_CODE")" "$(json_escape "$ERROR_SUMMARY")" "$(json_escape "$version")" >&2
}

is_hex() {
  expected_length=$1
  value=$2
  /usr/bin/awk -v value="$value" -v expected_length="$expected_length" \
    'BEGIN { exit !(length(value) == expected_length && value !~ /[^0-9a-f]/ && value !~ /^0+$/) }'
}

is_positive_integer() {
  /usr/bin/awk -v value="$1" 'BEGIN { exit !(value ~ /^[1-9][0-9]*$/) }'
}

is_semver() {
  /usr/bin/awk -v value="$1" \
    'BEGIN { exit !(value ~ /^[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$/) }'
}

check_resource() {
  path=$1
  if [ ! -f "$path" ] || [ -L "$path" ]; then
    fail plugin_incomplete "Plugin resource is missing or is not a regular file"
    return 1
  fi
}

is_safe_payload_path() {
  /usr/bin/awk -v value="$1" 'BEGIN {
    exit !(value ~ /^[A-Za-z0-9._\/-]+$/ && value !~ /^\// && value !~ /^[A-Za-z]:/ && value !~ /(^|\/)\.\.($|\/)/ && value !~ /(^|\/)\.($|\/)/ && value !~ /\/\//)
  }'
}

check_plugin() {
  [ -f "$MANIFEST_PATH" ] && [ ! -L "$MANIFEST_PATH" ] || {
    fail plugin_incomplete "Plugin manifest is missing"
    return 1
  }
  [ -f "$LOCK_PATH" ] && [ ! -L "$LOCK_PATH" ] || {
    fail plugin_incomplete "Runtime lock is missing"
    return 1
  }
  check_resource "$SCRIPT_DIR/scorace-runtime.sh" || return 1
  check_resource "$SCRIPT_DIR/scorace-runtime.ps1" || return 1
  check_resource "$PLUGIN_ROOT/learning-release.json" || return 1
  check_resource "$PLUGIN_ROOT/README.md" || return 1
  check_resource "$PLUGIN_ROOT/LICENSE" || return 1
  check_resource "$PLUGIN_ROOT/THIRD_PARTY_NOTICES.md" || return 1
  symlink=$(/usr/bin/find "$PLUGIN_ROOT" -type l -print -quit 2>/dev/null || true)
  [ -z "$symlink" ] || {
    fail plugin_incomplete "Public Plugin contains a symlink"
    return 1
  }
  if [ -e "$PLUGIN_ROOT/lib" ] || [ -L "$PLUGIN_ROOT/lib" ]; then
    fail plugin_incomplete "Public Plugin contains protected core files"
    return 1
  fi
  for private_path in \
    "$PLUGIN_ROOT/tools/study-assets.mjs" \
    "$PLUGIN_ROOT/tools/study-methods.mjs" \
    "$PLUGIN_ROOT/tools/teaching-renderer.mjs" \
    "$PLUGIN_ROOT/tools/interactive-demo.mjs" \
    "$PLUGIN_ROOT/tools/demo-cli.mjs" \
    "$PLUGIN_ROOT/tools/network-browser.mjs" \
    "$PLUGIN_ROOT/skills/scorace-study/scripts"; do
    if [ -e "$private_path" ] || [ -L "$private_path" ]; then
      fail plugin_incomplete "Public Plugin contains a private or legacy source entry"
      return 1
    fi
  done
  while IFS= read -r public_path; do
    case "$public_path" in
      *.js|*.mjs|*.cjs|*.ts|*.map)
        fail plugin_incomplete "Public Plugin contains a JavaScript or source-map payload"
        return 1
        ;;
    esac
  done <<EOF
$(/usr/bin/find "$PLUGIN_ROOT" -type f -print 2>/dev/null || true)
EOF
  return 0
}

check_platform() {
  product_name=$(/usr/bin/sw_vers -productName 2>/dev/null || true)
  os_major=$(/usr/bin/sw_vers -productVersion 2>/dev/null | /usr/bin/awk -F. 'NR == 1 { print $1 }' || true)
  architecture=$(/usr/bin/uname -m 2>/dev/null || true)
  translated=$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || printf '0')
  [ "$product_name" = "macOS" ] && [ "$os_major" = "26" ] && [ "$architecture" = "arm64" ] && [ "$translated" != "1" ] || {
    fail platform_unsupported "This Plugin supports native macOS 26 arm64 only"
    return 1
  }
  return 0
}

validate_archive_url() {
  target_name=$1
  encoded_version=$(printf '%s' "$PROGRAM_VERSION" | /usr/bin/sed 's/+/%2B/g')
  expected_url="https://github.com/scoracecom/plugins/releases/download/scorace-v${encoded_version}/scorace-${encoded_version}-${target_name}.zip"
  [ "$ARCHIVE_URL" = "$expected_url" ] || {
    fail runtime_lock_invalid "Runtime archive URL is not the fixed ScorAce release URL"
    return 1
  }
  return 0
}

payload_value() {
  target_lock_value "payload.$1.$2"
}

payload_contains() {
  wanted=$1
  index=0
  while [ "$index" -lt "$PAYLOAD_COUNT" ]; do
    [ "$(payload_value "$index" path)" = "$wanted" ] && return 0
    index=$((index + 1))
  done
  return 1
}

validate_lock() {
  schema=$(lock_value schema)
  manifest_name=$(manifest_value name)
  manifest_version=$(manifest_value version)
  lock_plugin_id=$(lock_value plugin_id)
  lock_plugin_version=$(lock_value plugin_version)
  PROGRAM_VERSION=$(lock_value program_version)
  program=$(lock_value program)
  cli_contract=$(lock_value cli_contract)
  learning_api=$(lock_value learning_api)
  state_contract=$(lock_value state_compatibility.contract)
  state_legacy=$(lock_value state_compatibility.legacy_read.0)
  state_write=$(lock_value state_compatibility.write_policy)
  source_revision=$(lock_value source_revision)
  source_tree_sha256=$(lock_value source_tree_sha256)

  [ "$schema" = "scorace-runtime-lock/v2" ] || {
    fail runtime_lock_invalid "Runtime lock schema is invalid"
    return 1
  }
  [ "$manifest_name" = "scorace-learning" ] && [ "$lock_plugin_id" = "$manifest_name" ] && \
    [ "$lock_plugin_version" = "$manifest_version" ] && [ -n "$manifest_version" ] || {
    fail runtime_lock_invalid "Runtime lock does not match Plugin identity"
    return 1
  }
  [ "$program" = "scorace" ] && [ -n "$PROGRAM_VERSION" ] && is_semver "$PROGRAM_VERSION" || {
    fail runtime_lock_invalid "Runtime program identity is missing or invalid"
    return 1
  }
  [ "$cli_contract" = "scorace-cli/v2" ] && [ "$learning_api" = "scorace-learning-api/v2" ] || {
    fail runtime_lock_invalid "Runtime CLI or learning API contract is invalid"
    return 1
  }
  [ "$state_contract" = "scorace-study-state/v2" ] && [ "$state_legacy" = "scorace-study-state/v1" ] && \
    [ "$state_write" = "baseline-preserving" ] || {
    fail runtime_lock_invalid "Runtime state compatibility is invalid"
    return 1
  }
  is_hex 40 "$source_revision" && is_hex 64 "$source_tree_sha256" || {
    fail runtime_lock_invalid "Runtime source identity is missing or invalid"
    return 1
  }
  [ "$(lock_value features.study)" = "true" ] && \
    [ "$(lock_value features.read_source)" = "false" ] && \
    [ "$(lock_value features.stdio_mcp)" = "false" ] || {
    fail runtime_lock_invalid "Runtime feature contract is invalid"
    return 1
  }
  validate_runtime_keys || return 1
  TARGET_PREFIX="runtimes.darwin-arm64"
  validate_runtime_entry darwin-arm64 || return 1
  TARGET_PREFIX="runtimes.windows-x64"
  validate_runtime_entry windows-x64 || return 1
  TARGET_PREFIX="runtimes.darwin-arm64"
  load_target_variables darwin-arm64
  load_target_payload || return 1
  return 0
}

validate_runtime_keys() {
  runtime_keys=$(/usr/bin/plutil -p "$LOCK_PATH" 2>/dev/null | /usr/bin/awk '
    /^  "runtimes" => \{$/ { inside = 1; next }
    inside && /^    "[^"]+" => \{$/ {
      value = $0
      sub(/^    "/, "", value)
      sub(/" => \{$/, "", value)
      print value
      next
    }
    inside && $0 !~ /^ / { inside = 0 }
  ')
  [ "$(printf '%s\n' "$runtime_keys" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')" = "2" ] && \
    printf '%s\n' "$runtime_keys" | /usr/bin/grep -Fxq darwin-arm64 && \
    printf '%s\n' "$runtime_keys" | /usr/bin/grep -Fxq windows-x64 || {
    fail runtime_lock_invalid "Runtime lock must contain exactly darwin-arm64 and windows-x64 targets"
    return 1
  }
  return 0
}

load_target_variables() {
  target_name=$1
  TARGET_PREFIX="runtimes.$target_name"
  target_os=$(target_lock_value target.os)
  target_arch=$(target_lock_value target.arch)
  target_min=$(target_lock_value target.os_major_min)
  target_max=$(target_lock_value target.os_major_max)
  PUBLISHER_TEAM_ID=$(target_lock_value system_trust.team_id)
  ARCHIVE_URL=$(target_lock_value archive.url)
  ARCHIVE_SHA256=$(target_lock_value archive.sha256)
  ARCHIVE_BYTES=$(target_lock_value archive.bytes)
  archive_format=$(target_lock_value archive.format)
  ARCHIVE_ROOT=$(target_lock_value archive.root)
  EXECUTABLE_PATH=$(target_lock_value executable.path)
  EXECUTABLE_SHA256=$(target_lock_value executable.sha256)
  EXECUTABLE_BYTES=$(target_lock_value executable.bytes)
}

validate_runtime_entry() {
  target_name=$1
  load_target_variables "$target_name"
  case "$target_name" in
    darwin-arm64)
      expected_os=darwin
      expected_arch=arm64
      expected_min=26
      expected_max=26
      expected_executable=bin/scorace
      trust_kind=$(target_lock_value system_trust.kind)
      [ "$trust_kind" = "apple_developer_id" ] || {
        fail runtime_lock_invalid "macOS runtime trust policy is invalid"
        return 1
      }
      case "$PUBLISHER_TEAM_ID" in
        ??????????) : ;;
        *) fail runtime_lock_invalid "Runtime publisher Team ID is missing or invalid"; return 1 ;;
      esac
      case "$PUBLISHER_TEAM_ID" in
        *[!A-Z0-9]*) fail runtime_lock_invalid "Runtime publisher Team ID is missing or invalid"; return 1 ;;
      esac
      ;;
    windows-x64)
      expected_os=windows
      expected_arch=x64
      expected_min=11
      expected_max=11
      expected_executable=bin/scorace.exe
      [ "$(target_lock_value system_trust.kind)" = "unsigned" ] && [ -z "$PUBLISHER_TEAM_ID" ] || {
        fail runtime_lock_invalid "Windows runtime trust policy must be explicitly unsigned"
        return 1
      }
      ;;
    *) fail runtime_lock_invalid "Runtime target is unsupported"; return 1 ;;
  esac
  [ "$target_os" = "$expected_os" ] && [ "$target_arch" = "$expected_arch" ] && \
    [ "$target_min" = "$expected_min" ] && [ "$target_max" = "$expected_max" ] || {
    fail runtime_lock_invalid "Runtime target is not the supported platform"
    return 1
  }
  [ "$EXECUTABLE_PATH" = "$expected_executable" ] && is_hex 64 "$EXECUTABLE_SHA256" && is_positive_integer "$EXECUTABLE_BYTES" || {
    fail runtime_lock_invalid "Runtime executable identity is missing or invalid"
    return 1
  }
  validate_archive_url "$target_name" || return 1
  is_hex 64 "$ARCHIVE_SHA256" && is_positive_integer "$ARCHIVE_BYTES" && [ "$archive_format" = "zip" ] || {
    fail runtime_lock_invalid "Runtime archive identity is missing or invalid"
    return 1
  }
  [ "$ARCHIVE_ROOT" = "scorace-${PROGRAM_VERSION}-${target_name}" ] || {
    fail runtime_lock_invalid "Runtime archive root is invalid"
    return 1
  }

  load_target_payload || return 1
  return 0
}

load_target_payload() {
  PAYLOAD_COUNT=0
  while :; do
    payload_path=$(payload_value "$PAYLOAD_COUNT" path)
    if [ -z "$payload_path" ]; then
      next_payload_path=$(payload_value $((PAYLOAD_COUNT + 1)) path)
      [ -z "$next_payload_path" ] || {
        fail runtime_lock_invalid "Runtime payload contains an unreadable entry"
        return 1
      }
      break
    fi
    is_safe_payload_path "$payload_path" || {
      fail runtime_lock_invalid "Runtime payload path is unsafe"
      return 1
    }
    [ "$payload_path" != ".scorace/runtime-lock.json" ] || {
      fail runtime_lock_invalid "Runtime payload cannot contain the Plugin lock"
      return 1
    }
    payload_role=$(payload_value "$PAYLOAD_COUNT" role)
    case "$payload_role" in
      runtime|public_resource|license|metadata) : ;;
      *) fail runtime_lock_invalid "Runtime payload role is invalid"; return 1 ;;
    esac
    payload_sha=$(payload_value "$PAYLOAD_COUNT" sha256)
    payload_bytes=$(payload_value "$PAYLOAD_COUNT" bytes)
    is_hex 64 "$payload_sha" && is_positive_integer "$payload_bytes" || {
      fail runtime_lock_invalid "Runtime payload digest is missing or invalid"
      return 1
    }
    if payload_contains "$payload_path"; then
      fail runtime_lock_invalid "Runtime payload contains duplicate paths"
      return 1
    fi
    PAYLOAD_COUNT=$((PAYLOAD_COUNT + 1))
  done
  [ "$PAYLOAD_COUNT" -gt 0 ] && payload_contains "$EXECUTABLE_PATH" && payload_contains "runtime-release.json" || {
    fail runtime_lock_invalid "Runtime payload is incomplete"
    return 1
  }
  release_payload_index=0
  while [ "$release_payload_index" -lt "$PAYLOAD_COUNT" ]; do
    [ "$(payload_value "$release_payload_index" path)" = "runtime-release.json" ] && break
    release_payload_index=$((release_payload_index + 1))
  done
  [ "$(payload_value "$release_payload_index" role)" = "metadata" ] || {
    fail runtime_lock_invalid "Runtime release metadata is not classified correctly"
    return 1
  }
  executable_payload_index=0
  while [ "$executable_payload_index" -lt "$PAYLOAD_COUNT" ]; do
    [ "$(payload_value "$executable_payload_index" path)" = "$EXECUTABLE_PATH" ] && break
    executable_payload_index=$((executable_payload_index + 1))
  done
  [ "$(payload_value "$executable_payload_index" sha256)" = "$EXECUTABLE_SHA256" ] && \
    [ "$(payload_value "$executable_payload_index" bytes)" = "$EXECUTABLE_BYTES" ] && \
    [ "$(payload_value "$executable_payload_index" role)" = "runtime" ] || {
    fail runtime_lock_invalid "Runtime executable is not represented by the payload"
    return 1
  }
  return 0
}

reject_symlink_components() {
  root=$1
  case "$root" in
    "$HOME"/*) : ;;
    *) fail runtime_root_unavailable "Managed runtime root must remain under HOME"; return 1 ;;
  esac
  component="$HOME"
  rest=${root#"$HOME"/}
  old_ifs=$IFS
  IFS=/
  for part in $rest; do
    [ -n "$part" ] || continue
    component="$component/$part"
    if [ -L "$component" ]; then
      IFS=$old_ifs
      fail runtime_root_unavailable "Managed runtime path contains a symlink"
      return 1
    fi
  done
  IFS=$old_ifs
  return 0
}

file_size() {
  /usr/bin/stat -f '%z' "$1" 2>/dev/null
}

file_nlink() {
  /usr/bin/stat -f '%l' "$1" 2>/dev/null
}

verify_file() {
  base=$1
  path=$2
  expected_sha=$3
  expected_bytes=$4
  file="$base/$path"
  [ -f "$file" ] && [ ! -L "$file" ] || {
    fail runtime_integrity_mismatch "Runtime file is missing"
    return 1
  }
  [ "$(file_size "$file")" = "$expected_bytes" ] || {
    fail runtime_integrity_mismatch "Runtime file size does not match the lock"
    return 1
  }
  [ "$(file_nlink "$file")" = "1" ] || {
    fail archive_invalid "Runtime archive contains a hardlink"
    return 1
  }
  actual_sha=$(/usr/bin/shasum -a 256 "$file" 2>/dev/null | /usr/bin/awk '{print $1}')
  [ "$actual_sha" = "$expected_sha" ] || {
    fail runtime_integrity_mismatch "Runtime file digest does not match the lock"
    return 1
  }
  return 0
}

verify_payload_tree() {
  base=$1
  [ -d "$base" ] && [ ! -L "$base" ] || {
    fail runtime_integrity_mismatch "Runtime directory is missing"
    return 1
  }
  symlink=$(/usr/bin/find "$base" -type l -print -quit 2>/dev/null || true)
  [ -z "$symlink" ] || {
    fail archive_invalid "Runtime archive contains a symlink"
    return 1
  }
  special=$(/usr/bin/find "$base" ! -type d ! -type f ! -type l -print -quit 2>/dev/null || true)
  [ -z "$special" ] || {
    fail archive_invalid "Runtime archive contains a special file"
    return 1
  }
  index=0
  while [ "$index" -lt "$PAYLOAD_COUNT" ]; do
    payload_path=$(payload_value "$index" path)
    verify_file "$base" "$payload_path" "$(payload_value "$index" sha256)" "$(payload_value "$index" bytes)" || return 1
    index=$((index + 1))
  done
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    relative=${file#"$base"/}
    payload_contains "$relative" || {
      fail runtime_integrity_mismatch "Runtime directory contains an unlisted file"
      return 1
    }
  done <<EOF
$(/usr/bin/find "$base" -type f -print 2>/dev/null || true)
EOF
  return 0
}

verify_release_metadata() {
  base=$1
  release="$base/runtime-release.json"
  release_schema=$(/usr/bin/plutil -extract schema raw -o - "$release" 2>/dev/null || true)
  release_program=$(/usr/bin/plutil -extract program raw -o - "$release" 2>/dev/null || true)
  release_version=$(/usr/bin/plutil -extract program_version raw -o - "$release" 2>/dev/null || true)
  release_source=$(/usr/bin/plutil -extract source_revision raw -o - "$release" 2>/dev/null || true)
  release_tree=$(/usr/bin/plutil -extract source_tree_sha256 raw -o - "$release" 2>/dev/null || true)
  release_cli=$(/usr/bin/plutil -extract cli_contract raw -o - "$release" 2>/dev/null || true)
  release_api=$(/usr/bin/plutil -extract learning_api raw -o - "$release" 2>/dev/null || true)
  release_state=$(/usr/bin/plutil -extract state_compatibility.contract raw -o - "$release" 2>/dev/null || true)
  release_legacy=$(/usr/bin/plutil -extract state_compatibility.legacy_read.0 raw -o - "$release" 2>/dev/null || true)
  release_write=$(/usr/bin/plutil -extract state_compatibility.write_policy raw -o - "$release" 2>/dev/null || true)
  release_target_os=$(/usr/bin/plutil -extract target.os raw -o - "$release" 2>/dev/null || true)
  release_target_arch=$(/usr/bin/plutil -extract target.arch raw -o - "$release" 2>/dev/null || true)
  release_target_min=$(/usr/bin/plutil -extract target.os_major_min raw -o - "$release" 2>/dev/null || true)
  release_target_max=$(/usr/bin/plutil -extract target.os_major_max raw -o - "$release" 2>/dev/null || true)
  release_study=$(/usr/bin/plutil -extract features.study raw -o - "$release" 2>/dev/null || true)
  release_reader=$(/usr/bin/plutil -extract features.read_source raw -o - "$release" 2>/dev/null || true)
  release_mcp=$(/usr/bin/plutil -extract features.stdio_mcp raw -o - "$release" 2>/dev/null || true)
  [ "$release_schema" = "scorace-runtime-release/v1" ] && [ "$release_program" = "scorace" ] && \
    [ "$release_version" = "$PROGRAM_VERSION" ] && [ "$release_source" = "$source_revision" ] && \
    [ "$release_tree" = "$source_tree_sha256" ] && [ "$release_cli" = "scorace-cli/v2" ] && \
    [ "$release_api" = "scorace-learning-api/v2" ] && [ "$release_state" = "scorace-study-state/v2" ] && \
    [ "$release_legacy" = "scorace-study-state/v1" ] && [ "$release_write" = "baseline-preserving" ] && \
    [ "$release_target_os" = "darwin" ] && [ "$release_target_arch" = "arm64" ] && \
    [ "$release_target_min" = "26" ] && [ "$release_target_max" = "26" ] && \
    [ "$release_study" = "true" ] && [ "$release_reader" = "false" ] && [ "$release_mcp" = "false" ] || {
    fail runtime_incompatible "Runtime release metadata does not match the lock"
    return 1
  }
  return 0
}

verify_signature() {
  executable=$1
  [ -x "$executable" ] || {
    fail runtime_integrity_mismatch "Runtime executable is not executable"
    return 1
  }
  [ -x /usr/bin/codesign ] || {
    fail system_trust_unavailable "macOS code-signing verification is unavailable"
    return 1
  }
  /usr/bin/codesign --verify --strict --verbose=2 "$executable" >/dev/null 2>&1 || {
    fail runtime_signature_invalid "Runtime code signature is invalid"
    return 1
  }
  trust_requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$PUBLISHER_TEAM_ID\""
  /usr/bin/codesign --verify --strict "-R=$trust_requirement" "$executable" >/dev/null 2>&1 || {
    fail runtime_signature_invalid "Runtime signature does not satisfy the Apple Developer ID trust requirement"
    return 1
  }
  signature=$(/usr/bin/codesign -dv --verbose=4 "$executable" 2>&1 || true)
  authority=$(printf '%s\n' "$signature" | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -1)
  authority_team=$(printf '%s\n' "$authority" | /usr/bin/sed -n 's/^Developer ID Application: .* (\([A-Z0-9]*\))$/\1/p')
  [ -n "$authority_team" ] && [ "$authority_team" = "$PUBLISHER_TEAM_ID" ] || {
    fail runtime_signature_invalid "Runtime signature is not a Developer ID Application for the locked Team ID"
    return 1
  }
  team_id=$(printf '%s\n' "$signature" | /usr/bin/sed -n 's/^TeamIdentifier=//p' | /usr/bin/tail -1)
  [ "$team_id" = "$PUBLISHER_TEAM_ID" ] || {
    fail runtime_signature_invalid "Runtime signing Team ID does not match the lock"
    return 1
  }
  code_directory=$(printf '%s\n' "$signature" | /usr/bin/sed -n '/^CodeDirectory /p' | /usr/bin/head -1)
  flags=$(printf '%s\n' "$code_directory" | /usr/bin/sed -n 's/.* flags=\([^ ]*\).*/\1/p')
  case "$flags" in
    0x[0-9A-Fa-f]*\(runtime\)) : ;;
    *)
      fail runtime_signature_invalid "Runtime signature does not enable the hardened runtime"
      return 1
      ;;
  esac
  timestamp=$(printf '%s\n' "$signature" | /usr/bin/sed -n 's/^Timestamp=//p' | /usr/bin/tail -1)
  case "$timestamp" in
    ''|none|NONE)
      fail runtime_signature_invalid "Runtime signature does not contain a secure timestamp"
      return 1
      ;;
  esac
  return 0
}

verify_version() {
  executable=$1
  version_json=$("$executable" version 2>/dev/null) || {
    fail runtime_incompatible "Runtime version probe failed"
    return 1
  }
  version_schema=$(printf '%s' "$version_json" | /usr/bin/plutil -extract schema raw -o - - 2>/dev/null || true)
  version_program=$(printf '%s' "$version_json" | /usr/bin/plutil -extract program raw -o - - 2>/dev/null || true)
  version_value=$(printf '%s' "$version_json" | /usr/bin/plutil -extract program_version raw -o - - 2>/dev/null || true)
  version_source=$(printf '%s' "$version_json" | /usr/bin/plutil -extract source_revision raw -o - - 2>/dev/null || true)
  version_tree=$(printf '%s' "$version_json" | /usr/bin/plutil -extract source_tree_sha256 raw -o - - 2>/dev/null || true)
  version_cli=$(printf '%s' "$version_json" | /usr/bin/plutil -extract cli_contract raw -o - - 2>/dev/null || true)
  version_api=$(printf '%s' "$version_json" | /usr/bin/plutil -extract learning_api raw -o - - 2>/dev/null || true)
  version_state=$(printf '%s' "$version_json" | /usr/bin/plutil -extract state_compatibility.contract raw -o - - 2>/dev/null || true)
  version_legacy=$(printf '%s' "$version_json" | /usr/bin/plutil -extract state_compatibility.legacy_read.0 raw -o - - 2>/dev/null || true)
  version_write=$(printf '%s' "$version_json" | /usr/bin/plutil -extract state_compatibility.write_policy raw -o - - 2>/dev/null || true)
  version_target_os=$(printf '%s' "$version_json" | /usr/bin/plutil -extract target.os raw -o - - 2>/dev/null || true)
  version_target_arch=$(printf '%s' "$version_json" | /usr/bin/plutil -extract target.arch raw -o - - 2>/dev/null || true)
  version_target_min=$(printf '%s' "$version_json" | /usr/bin/plutil -extract target.os_major_min raw -o - - 2>/dev/null || true)
  version_target_max=$(printf '%s' "$version_json" | /usr/bin/plutil -extract target.os_major_max raw -o - - 2>/dev/null || true)
  version_study=$(printf '%s' "$version_json" | /usr/bin/plutil -extract features.study raw -o - - 2>/dev/null || true)
  version_reader=$(printf '%s' "$version_json" | /usr/bin/plutil -extract features.read_source raw -o - - 2>/dev/null || true)
  version_mcp=$(printf '%s' "$version_json" | /usr/bin/plutil -extract features.stdio_mcp raw -o - - 2>/dev/null || true)
  [ "$version_schema" = "scorace-runtime-version/v1" ] && [ "$version_program" = "scorace" ] && \
    [ "$version_value" = "$PROGRAM_VERSION" ] && [ "$version_source" = "$source_revision" ] && \
    [ "$version_tree" = "$source_tree_sha256" ] && [ "$version_cli" = "scorace-cli/v2" ] && \
    [ "$version_api" = "scorace-learning-api/v2" ] && [ "$version_state" = "scorace-study-state/v2" ] && \
    [ "$version_legacy" = "scorace-study-state/v1" ] && [ "$version_write" = "baseline-preserving" ] && \
    [ "$version_target_os" = "darwin" ] && [ "$version_target_arch" = "arm64" ] && \
    [ "$version_target_min" = "26" ] && [ "$version_target_max" = "26" ] && \
    [ "$version_study" = "true" ] && [ "$version_reader" = "false" ] && [ "$version_mcp" = "false" ] || {
    fail runtime_incompatible "Runtime version does not match the lock"
    return 1
  }
  return 0
}

validate_installed() {
  TARGET_ROOT="$RUNTIME_ROOT/$PROGRAM_VERSION/$TARGET_KEY"
  reject_symlink_components "$TARGET_ROOT" || return 1
  [ -d "$TARGET_ROOT" ] && [ ! -L "$TARGET_ROOT" ] || {
    fail dependency_missing "The locked scorace runtime is not installed"
    return 1
  }
  verify_payload_tree "$TARGET_ROOT" || return 1
  verify_release_metadata "$TARGET_ROOT" || return 1
  verify_signature "$TARGET_ROOT/$EXECUTABLE_PATH" || return 1
  verify_version "$TARGET_ROOT/$EXECUTABLE_PATH" || return 1
  return 0
}

validate_common() {
  case "${HOME:-}" in
    /*) : ;;
    *) fail runtime_root_unavailable "HOME is not an absolute user directory"; return 1 ;;
  esac
  check_plugin || return 1
  check_platform || return 1
  validate_lock || return 1
  return 0
}

check() {
  validate_common || { emit_error; return 1; }
  validate_installed || { emit_error; return 1; }
  executable="$RUNTIME_ROOT/$PROGRAM_VERSION/$TARGET_KEY/$EXECUTABLE_PATH"
  printf '{"status":"ok","operation":"runtime.check","ready":true,"program":"scorace","program_version":"%s","target":"%s","executable":"%s"}\n' \
    "$(json_escape "$PROGRAM_VERSION")" "$(json_escape "$TARGET_KEY")" "$(json_escape "$executable")"
  return 0
}

ensure_runtime_root() {
  case "${HOME:-}" in
    /*) : ;;
    *) fail runtime_root_unavailable "HOME is not an absolute user directory"; return 1 ;;
  esac
  reject_symlink_components "$RUNTIME_ROOT" || return 1
  if [ -e "$RUNTIME_ROOT" ] && [ ! -d "$RUNTIME_ROOT" ]; then
    fail runtime_root_unavailable "Managed runtime root is not a directory"
    return 1
  fi
  /bin/mkdir -p "$RUNTIME_ROOT" 2>/dev/null || {
    fail runtime_root_unavailable "Managed runtime root cannot be created"
    return 1
  }
  return 0
}

release_lock() {
  if [ "$OWNS_LOCK" -eq 1 ]; then
    /bin/rm -f "$INSTALL_LOCK/pid" 2>/dev/null || true
    /bin/rmdir "$INSTALL_LOCK" 2>/dev/null || true
    OWNS_LOCK=0
  fi
}

cleanup() {
  release_lock
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then
    /bin/rm -rf "$STAGE"
  fi
}

acquire_lock() {
  INSTALL_LOCK="$RUNTIME_ROOT/.install.lock"
  if /bin/mkdir "$INSTALL_LOCK" 2>/dev/null; then
    OWNS_LOCK=1
    printf '%s\n' "$$" > "$INSTALL_LOCK/pid"
    return 0
  fi
  [ -L "$INSTALL_LOCK" ] && {
    fail runtime_root_unavailable "Managed install lock is a symlink"
    return 1
  }
  attempts=0
  while [ "$attempts" -lt 120 ]; do
    if [ -L "$INSTALL_LOCK/pid" ]; then
      fail runtime_root_unavailable "Managed install lock pid is a symlink"
      return 1
    fi
    if [ ! -f "$INSTALL_LOCK/pid" ]; then
      if /bin/mkdir "$INSTALL_LOCK" 2>/dev/null; then
        OWNS_LOCK=1
        printf '%s\n' "$$" > "$INSTALL_LOCK/pid"
        return 0
      fi
      attempts=$((attempts + 1))
      /bin/sleep 1
      continue
    fi
    if [ -f "$INSTALL_LOCK/pid" ] && [ ! -L "$INSTALL_LOCK/pid" ]; then
      owner=$(/usr/bin/sed -n '1p' "$INSTALL_LOCK/pid" 2>/dev/null || true)
      case "$owner" in
        ''|*[!0-9]*) : ;;
        *) /bin/kill -0 "$owner" 2>/dev/null && { /bin/sleep 1; attempts=$((attempts + 1)); continue; } ;;
      esac
    fi
    /bin/rm -f "$INSTALL_LOCK/pid" 2>/dev/null || true
    /bin/rmdir "$INSTALL_LOCK" 2>/dev/null || true
    if /bin/mkdir "$INSTALL_LOCK" 2>/dev/null; then
      OWNS_LOCK=1
      printf '%s\n' "$$" > "$INSTALL_LOCK/pid"
      return 0
    fi
    attempts=$((attempts + 1))
    /bin/sleep 1
  done
  fail install_busy "Another runtime installation is still in progress"
  return 1
}

verify_archive_file() {
  archive=$1
  [ -f "$archive" ] && [ ! -L "$archive" ] || {
    fail archive_invalid "Runtime archive is missing"
    return 1
  }
  [ "$(file_size "$archive")" = "$ARCHIVE_BYTES" ] || {
    fail archive_invalid "Runtime archive size does not match the lock"
    return 1
  }
  actual_sha=$(/usr/bin/shasum -a 256 "$archive" 2>/dev/null | /usr/bin/awk '{print $1}')
  [ "$actual_sha" = "$ARCHIVE_SHA256" ] || {
    fail archive_invalid "Runtime archive digest does not match the lock"
    return 1
  }
  return 0
}

validate_zip_names() {
  archive=$1
  names=$(/usr/bin/unzip -Z1 "$archive" 2>/dev/null) || {
    fail archive_invalid "Runtime archive is not a readable ZIP"
    return 1
  }
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    is_safe_payload_path "$name" || {
      fail archive_invalid "Runtime archive contains an unsafe path"
      return 1
    }
    case "$name" in
      "$ARCHIVE_ROOT"|"$ARCHIVE_ROOT"/*) : ;;
      *) fail archive_invalid "Runtime archive has an unexpected root"; return 1 ;;
    esac
  done <<EOF
$names
EOF
  duplicate=$(/usr/bin/printf '%s\n' "$names" | /usr/bin/sort | /usr/bin/uniq -d | /usr/bin/head -1)
  [ -z "$duplicate" ] || {
    fail archive_invalid "Runtime archive contains a duplicate path"
    return 1
  }
  return 0
}

validate_zip_types() {
  archive=$1
  names=$(/usr/bin/unzip -Z1 "$archive" 2>/dev/null) || {
    fail archive_invalid "Runtime archive is not a readable ZIP"
    return 1
  }
  listing=$(/usr/bin/zipinfo -l "$archive" 2>/dev/null) || {
    fail archive_invalid "Runtime archive metadata is not readable"
    return 1
  }
  bad_mode=$(printf '%s\n' "$listing" | /usr/bin/awk 'length($1) == 10 && $1 ~ /^[a-z-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-]$/ && $1 !~ /^[d-]/ { print $1; exit }')
  [ -z "$bad_mode" ] || {
    fail archive_invalid "Runtime archive contains a symlink or non-regular entry"
    return 1
  }
  mode_count=$(printf '%s\n' "$listing" | /usr/bin/awk 'length($1) == 10 && $1 ~ /^[a-z-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-][rwxstST-]$/ { count += 1 } END { print count + 0 }')
  name_count=$(printf '%s\n' "$names" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
  [ "$mode_count" = "$name_count" ] || {
    fail archive_invalid "Runtime archive metadata does not describe every entry"
    return 1
  }
  return 0
}

candidate_version_check() {
  base=$1
  TARGET_ROOT="$base"
  verify_payload_tree "$base" || return 1
  verify_release_metadata "$base" || return 1
  verify_signature "$base/$EXECUTABLE_PATH" || return 1
  verify_version "$base/$EXECUTABLE_PATH" || return 1
  return 0
}

prepare() {
  mode=${1:-}
  [ "$#" -gt 0 ] && shift
  case "$mode" in
    --allow-download)
      [ "$#" -eq 0 ] || { fail invalid_command "prepare --allow-download takes no path"; emit_error; return 1; }
      source_mode=download
      ;;
    --archive)
      [ "$#" -eq 1 ] || { fail invalid_command "prepare --archive requires one absolute ZIP path"; emit_error; return 1; }
      archive_source=$1
      case "$archive_source" in
        /*) : ;;
        *) fail invalid_command "prepare --archive requires one absolute ZIP path"; emit_error; return 1 ;;
      esac
      source_mode=archive
      ;;
    *)
      fail invalid_command "prepare requires --allow-download or --archive"
      emit_error
      return 1
      ;;
  esac

  validate_common || { emit_error; return 1; }
  ensure_runtime_root || { emit_error; return 1; }
  acquire_lock || { emit_error; return 1; }
  trap cleanup EXIT
  trap 'cleanup; exit 130' HUP INT TERM

  if validate_installed; then
    executable="$RUNTIME_ROOT/$PROGRAM_VERSION/$TARGET_KEY/$EXECUTABLE_PATH"
    printf '{"status":"ok","operation":"runtime.prepare","ready":true,"result":"reused","program":"scorace","program_version":"%s","target":"%s","executable":"%s"}\n' \
      "$(json_escape "$PROGRAM_VERSION")" "$(json_escape "$TARGET_KEY")" "$(json_escape "$executable")"
    return 0
  fi
  TARGET_ROOT="$RUNTIME_ROOT/$PROGRAM_VERSION/$TARGET_KEY"
  reject_symlink_components "$TARGET_ROOT" || { emit_error; return 1; }

  STAGE=$(/usr/bin/mktemp -d "$RUNTIME_ROOT/.prepare-${PROGRAM_VERSION}.XXXXXX" 2>/dev/null) || {
    fail install_failed "Runtime staging directory cannot be created"
    emit_error
    return 1
  }
  archive_copy="$STAGE/runtime.zip"
  if [ "$source_mode" = "download" ]; then
    /usr/bin/curl --fail --location --silent --show-error --connect-timeout 30 --max-time 600 \
      "$ARCHIVE_URL" --output "$archive_copy" 2>/dev/null || {
      fail download_failed "Runtime archive download failed"
      emit_error
      return 1
    }
  else
    [ -f "$archive_source" ] && [ ! -L "$archive_source" ] || {
      fail archive_invalid "Runtime archive is missing"
      emit_error
      return 1
    }
    /bin/cp "$archive_source" "$archive_copy" 2>/dev/null || {
      fail archive_invalid "Runtime archive cannot be staged"
      emit_error
      return 1
    }
  fi
  verify_archive_file "$archive_copy" || { emit_error; return 1; }
  validate_zip_names "$archive_copy" || { emit_error; return 1; }
  validate_zip_types "$archive_copy" || { emit_error; return 1; }
  extracted="$STAGE/extracted"
  /bin/mkdir "$extracted" 2>/dev/null || {
    fail install_failed "Runtime archive staging failed"
    emit_error
    return 1
  }
  /usr/bin/unzip -q "$archive_copy" -d "$extracted" 2>/dev/null || {
    fail archive_invalid "Runtime archive extraction failed"
    emit_error
    return 1
  }
  candidate="$extracted/$ARCHIVE_ROOT"
  [ -d "$candidate" ] && [ ! -L "$candidate" ] || {
    fail archive_invalid "Runtime archive root is missing"
    emit_error
    return 1
  }
  candidate_version_check "$candidate" || { emit_error; return 1; }

  version_parent="$RUNTIME_ROOT/$PROGRAM_VERSION"
  [ ! -e "$version_parent" ] || [ -d "$version_parent" ] || {
    fail runtime_root_unavailable "Locked runtime version path is not a directory"
    emit_error
    return 1
  }
  /bin/mkdir -p "$version_parent" 2>/dev/null || {
    fail install_failed "Runtime version directory cannot be created"
    emit_error
    return 1
  }
  target="$version_parent/$TARGET_KEY"
  backup=
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="$version_parent/.previous-$TARGET_KEY-$$"
    [ ! -e "$backup" ] && [ ! -L "$backup" ] || {
      fail install_failed "Existing runtime backup path is unavailable"
      emit_error
      return 1
    }
    /bin/mv "$target" "$backup" 2>/dev/null || {
      fail install_failed "Existing runtime could not be preserved"
      emit_error
      return 1
    }
  fi
  if ! /bin/mv "$candidate" "$target" 2>/dev/null; then
    [ -n "$backup" ] && /bin/mv "$backup" "$target" 2>/dev/null || true
    fail install_failed "Runtime could not be published"
    emit_error
    return 1
  fi
  executable="$target/$EXECUTABLE_PATH"
  printf '{"status":"ok","operation":"runtime.prepare","ready":true,"result":"installed","program":"scorace","program_version":"%s","target":"%s","executable":"%s"}\n' \
    "$(json_escape "$PROGRAM_VERSION")" "$(json_escape "$TARGET_KEY")" "$(json_escape "$executable")"
  return 0
}

run_program() {
  [ "$#" -gt 0 ] || {
    fail invalid_command "run requires a scorace command"
    emit_error
    return 1
  }
  validate_common || { emit_error; return 1; }
  validate_installed || { emit_error; return 1; }
  if [ -z "${SCORACE_SESSION_ID:-}" ]; then
    if [ -n "${CODEX_THREAD_ID:-}" ]; then
      SCORACE_SESSION_ID=$CODEX_THREAD_ID
      export SCORACE_SESSION_ID
    elif [ -n "${CODEX_SESSION_ID:-}" ]; then
      SCORACE_SESSION_ID=$CODEX_SESSION_ID
      export SCORACE_SESSION_ID
    fi
  fi
  method_root="${CODEX_HOME:-${HOME:-}/.codex}/skills"
  if [ -z "${SCORACE_METHOD_ROOTS:-}" ]; then
    SCORACE_METHOD_ROOTS="[\"$(json_escape "$method_root")\"]"
  else
    method_roots=$(printf '%s' "$SCORACE_METHOD_ROOTS" | /usr/bin/awk 'BEGIN { RS = "\0" } { sub(/^[ \t\r\n]*/, ""); sub(/[ \t\r\n]*$/, ""); printf "%s", $0 }')
    case "$method_roots" in
      \[*\])
        method_root_items=${method_roots#\[}
        method_root_items=${method_root_items%\]}
        if [ -z "$(printf '%s' "$method_root_items" | /usr/bin/awk 'BEGIN { RS = "\0" } { gsub(/[ \t\r\n]/, ""); printf "%s", $0 }')" ]; then
          SCORACE_METHOD_ROOTS="[\"$(json_escape "$method_root")\"]"
        else
          SCORACE_METHOD_ROOTS="${method_roots%]},\"$(json_escape "$method_root")\"]"
        fi
        ;;
    esac
  fi
  export SCORACE_METHOD_ROOTS
  exec "$RUNTIME_ROOT/$PROGRAM_VERSION/$TARGET_KEY/$EXECUTABLE_PATH" "$@"
}

command=${1:-}
[ "$#" -gt 0 ] && shift
case "$command" in
  check)
    [ "$#" -eq 0 ] || { fail invalid_command "check takes no arguments"; emit_error; exit 1; }
    check
    ;;
  prepare)
    prepare "$@"
    ;;
  run)
    run_program "$@"
    ;;
  *)
    fail invalid_command "usage: scorace-runtime.sh check|prepare --allow-download|prepare --archive ZIP|run scorace-command"
    emit_error
    exit 1
    ;;
esac
