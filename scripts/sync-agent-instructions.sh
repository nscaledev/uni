#!/usr/bin/env bash

set -euo pipefail

readonly BEGIN_MARKER='<!-- BEGIN UNI SHARED INSTRUCTIONS -->'
readonly END_MARKER='<!-- END UNI SHARED INSTRUCTIONS -->'

fail() {
  echo "error: $*" >&2
  exit 1
}

if [[ $# -ne 4 ]]; then
  echo "usage: $0 SHARED_FILE TARGET_DIR AGENTS_PATH CLAUDE_PATH" >&2
  exit 2
fi

readonly shared_file="$1"
readonly target_dir="$2"
readonly agents_path="$3"
readonly claude_path="$4"
readonly agents_file="${target_dir}/${agents_path}"
readonly claude_file="${target_dir}/${claude_path}"
readonly import_line="@$(basename "$agents_path")"

[[ -s "$shared_file" ]] || fail "shared instructions not found or empty: $shared_file"
[[ -d "$target_dir" ]] || fail "target repository not found: $target_dir"

for path in "$agents_path" "$claude_path"; do
  [[ -n "$path" && "$path" != /* && "/$path/" != *'/../'* ]] || \
    fail "target file paths must be safe repository-relative paths"
done

[[ "$agents_path" != "$claude_path" ]] || \
  fail "AGENTS.md and CLAUDE.md paths must be different"
[[ "$(dirname "$agents_path")" == "$(dirname "$claude_path")" ]] || \
  fail "AGENTS.md and CLAUDE.md must be in the same directory"

if grep -Fqx "$BEGIN_MARKER" "$shared_file" || \
  grep -Fqx "$END_MARKER" "$shared_file"; then
  fail "shared instructions must not contain managed markers"
fi

temporary_file=''
cleanup() {
  [[ -z "$temporary_file" || ! -e "$temporary_file" ]] || rm -f "$temporary_file"
}
trap cleanup EXIT

new_temporary_file() {
  temporary_file="$(mktemp "$1.tmp.XXXXXX")"
}

install_temporary_file() {
  chmod 0644 "$temporary_file"
  mv "$temporary_file" "$1"
  temporary_file=''
}

mkdir -p "$(dirname "$agents_file")"

if [[ ! -e "$agents_file" ]]; then
  new_temporary_file "$agents_file"
  {
    printf '%s\n' "$BEGIN_MARKER"
    awk '{ print }' "$shared_file"
    printf '%s\n' "$END_MARKER"
  } >"$temporary_file"
  install_temporary_file "$agents_file"
  echo "created: $agents_file"
else
  [[ -f "$agents_file" && ! -L "$agents_file" ]] || \
    fail "$agents_file must be a regular file"

  begin_count="$(grep -Fxc "$BEGIN_MARKER" "$agents_file" || true)"
  end_count="$(grep -Fxc "$END_MARKER" "$agents_file" || true)"

  new_temporary_file "$agents_file"
  if [[ "$begin_count" -eq 0 && "$end_count" -eq 0 ]]; then
    {
      printf '%s\n' "$BEGIN_MARKER"
      awk '{ print }' "$shared_file"
      printf '%s\n\n' "$END_MARKER"
      cat "$agents_file"
    } >"$temporary_file"
  elif ! awk \
    -v begin="$BEGIN_MARKER" \
    -v finish="$END_MARKER" \
    -v source="$shared_file" '
        $0 == begin {
          if (saw_begin || saw_end) invalid = 1
          print
          while ((getline line < source) > 0) print line
          close(source)
          saw_begin = 1
          inside = 1
          next
        }
        $0 == finish {
          if (!inside || saw_end) invalid = 1
          inside = 0
          saw_end = 1
          print
          next
        }
        !inside { print }
        END {
          if (!saw_begin || !saw_end || inside || invalid) exit 2
        }
      ' "$agents_file" >"$temporary_file"; then
    fail "$agents_file must contain exactly one correctly ordered marker pair"
  fi

  if cmp -s "$temporary_file" "$agents_file"; then
    rm -f "$temporary_file"
    temporary_file=''
    echo "unchanged: $agents_file"
  else
    install_temporary_file "$agents_file"
    echo "updated: $agents_file"
  fi
fi

if [[ -L "$claude_file" ]]; then
  link_target="$(readlink "$claude_file")"
  [[ "$link_target" == "$(basename "$agents_path")" || \
    "$link_target" == "./$(basename "$agents_path")" ]] || \
    fail "$claude_file must link to $(basename "$agents_path")"
  echo "unchanged: $claude_file"
elif [[ ! -e "$claude_file" ]]; then
  new_temporary_file "$claude_file"
  printf '%s\n' "$import_line" >"$temporary_file"
  install_temporary_file "$claude_file"
  echo "created: $claude_file"
elif [[ ! -f "$claude_file" ]]; then
  fail "$claude_file must be a regular file"
elif grep -Fqx "$import_line" "$claude_file"; then
  echo "unchanged: $claude_file"
else
  new_temporary_file "$claude_file"
  {
    printf '%s\n\n' "$import_line"
    cat "$claude_file"
  } >"$temporary_file"
  install_temporary_file "$claude_file"
  echo "updated: $claude_file"
fi
