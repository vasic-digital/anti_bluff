#!/usr/bin/env bash
# anti_bluff — shared helpers for the status-custody seam (sourced, not executed).
# Zero project literals (§11.4.28/§11.4.177): every project-specific value is
# consumer DATA supplied via arguments or environment.
#
#   AB_TERMINAL_STATUSES  comma-separated terminal-status literals
#                         (default: Fixed,Implemented,Completed)
#   SQLITE                sqlite3 binary (default: sqlite3)

# ab_terminal_list -> prints a SQL-quoted IN-list built from AB_TERMINAL_STATUSES.
# Single quotes inside literals are SQL-escaped ('') so consumer vocabulary like
# "Fixed (→ Fixed.md)" travels intact.
ab_terminal_list() {
  local raw="${AB_TERMINAL_STATUSES:-Fixed,Implemented,Completed}" out="" item
  local IFS=','
  for item in $raw; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "$item" ] || continue
    item="${item//"'"/"''"}"
    out="$out,'$item'"
  done
  if [ -z "$out" ]; then
    echo "AB-CONFIG-INVALID: AB_TERMINAL_STATUSES produced an empty terminal-status list" >&2
    return 1
  fi
  printf '%s' "${out#,}"
}

# ab_first_terminal -> the first terminal literal (used by the live probe).
ab_first_terminal() {
  local raw="${AB_TERMINAL_STATUSES:-Fixed,Implemented,Completed}" item
  local IFS=','
  for item in $raw; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "$item" ] && { printf '%s' "$item"; return 0; }
  done
  return 1
}
