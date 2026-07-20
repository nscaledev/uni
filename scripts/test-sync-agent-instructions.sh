#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly sync_script="${script_dir}/sync-agent-instructions.sh"
readonly fixture_root="$(mktemp -d /tmp/sync-agent-instructions.XXXXXX)"
readonly shared_file="${fixture_root}/shared.md"

cleanup() {
  rm -rf "$fixture_root"
}
trap cleanup EXIT

fail() {
  echo "test failure: $*" >&2
  exit 1
}

assert_line() {
  grep -Fqx -- "$1" "$2" || fail "expected '$1' in $2"
}

run_sync() {
  "$sync_script" "$shared_file" "$1" AGENTS.md CLAUDE.md >/dev/null
}

printf '%s\n' '# Test shared instructions' 'Fixture content.' >"$shared_file"

# Missing files are created, and a second run makes no changes.
create_fixture="${fixture_root}/create"
mkdir -p "$create_fixture"
run_sync "$create_fixture"
assert_line '<!-- BEGIN UNI SHARED INSTRUCTIONS -->' "${create_fixture}/AGENTS.md"
assert_line '# Test shared instructions' "${create_fixture}/AGENTS.md"
assert_line '# Repository-specific instructions' "${create_fixture}/AGENTS.md"
assert_line '@AGENTS.md' "${create_fixture}/CLAUDE.md"
before="$(cksum "${create_fixture}/AGENTS.md" "${create_fixture}/CLAUDE.md")"
run_sync "$create_fixture"
after="$(cksum "${create_fixture}/AGENTS.md" "${create_fixture}/CLAUDE.md")"
[[ "$before" == "$after" ]] || fail 'sync is not idempotent'

# Existing markerless instructions are retained as repository-owned content.
bootstrap_fixture="${fixture_root}/bootstrap"
mkdir -p "$bootstrap_fixture"
printf '%s\n' '# Existing agent rules' '- Keep this rule.' >"${bootstrap_fixture}/AGENTS.md"
printf '%s\n' '# Existing Claude rules' '- Keep this too.' >"${bootstrap_fixture}/CLAUDE.md"
run_sync "$bootstrap_fixture"
assert_line '# Existing agent rules' "${bootstrap_fixture}/AGENTS.md"
assert_line '- Keep this rule.' "${bootstrap_fixture}/AGENTS.md"
[[ "$(sed -n '1p' "${bootstrap_fixture}/CLAUDE.md")" == '@AGENTS.md' ]] || \
  fail 'AGENTS.md import was not prepended to CLAUDE.md'
assert_line '- Keep this too.' "${bootstrap_fixture}/CLAUDE.md"

# An existing managed section is replaced without changing surrounding content.
update_fixture="${fixture_root}/update"
mkdir -p "$update_fixture"
printf '%s\n' \
  '# Local preamble' \
  '<!-- BEGIN UNI SHARED INSTRUCTIONS -->' \
  'obsolete shared content' \
  '<!-- END UNI SHARED INSTRUCTIONS -->' \
  '# Local rules' \
  '- Keep this local rule.' >"${update_fixture}/AGENTS.md"
run_sync "$update_fixture"
assert_line '# Local preamble' "${update_fixture}/AGENTS.md"
assert_line '- Keep this local rule.' "${update_fixture}/AGENTS.md"
if grep -Fq 'obsolete shared content' "${update_fixture}/AGENTS.md"; then
  fail 'obsolete managed content was retained'
fi

# Partial markers fail without modifying the existing file.
malformed_fixture="${fixture_root}/malformed"
mkdir -p "$malformed_fixture"
printf '%s\n' '<!-- BEGIN UNI SHARED INSTRUCTIONS -->' 'partial content' \
  >"${malformed_fixture}/AGENTS.md"
cp "${malformed_fixture}/AGENTS.md" "${malformed_fixture}/before"
if run_sync "$malformed_fixture" >/dev/null 2>&1; then
  fail 'partial markers were accepted'
fi
cmp -s "${malformed_fixture}/before" "${malformed_fixture}/AGENTS.md" || \
  fail 'malformed AGENTS.md was modified'

# A CLAUDE.md symlink to AGENTS.md is left intact.
symlink_fixture="${fixture_root}/symlink"
mkdir -p "$symlink_fixture"
ln -s AGENTS.md "${symlink_fixture}/CLAUDE.md"
run_sync "$symlink_fixture"
[[ -L "${symlink_fixture}/CLAUDE.md" ]] || fail 'CLAUDE.md symlink was replaced'
[[ "$(readlink "${symlink_fixture}/CLAUDE.md")" == 'AGENTS.md' ]] || \
  fail 'CLAUDE.md symlink target changed'

echo 'sync-agent-instructions tests passed'
