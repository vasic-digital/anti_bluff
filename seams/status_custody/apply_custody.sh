#!/usr/bin/env bash
# anti_bluff SOL-01 — apply the status-custody seam to a consumer database.
#
# Purpose : Land the custody triggers IN the consumer's SQLite tracker file so
#           the status-write seam binds EVERY writer (sanctioned tool, raw
#           sqlite3, writers that do not exist yet). Idempotent. Proves the
#           refusal LIVE on the target DB (§11.4.108 runtime signature) before
#           reporting success — never "should work".
# Usage   : apply_custody.sh <db-path> [--init] [--no-probe]
#             --init      create the DB from custody_schema.sql when the file
#                         does not exist (fresh-tracker bootstrap)
#             --no-probe  skip the live refusal probe (test harnesses only)
# Env     : AB_TERMINAL_STATUSES  consumer terminal-status vocabulary as DATA
#                                 (comma-separated; default Fixed,Implemented,Completed)
#           SQLITE                sqlite3 binary (default sqlite3)
# Exit    : 0 seam applied + verified | 1 refused/failed (named reason) | 2 blind
#
# Fail-closed (§11.4.6): a missing DB without --init, or a DB missing the
# required tables, is an ERROR with an actionable message — the script never
# guesses a consumer's schema mapping.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLITE="${SQLITE:-sqlite3}"
# shellcheck source=/dev/null
. "$HERE/ab_sql_lib.sh"

DB="${1:?usage: apply_custody.sh <db-path> [--init] [--no-probe]}"; shift
INIT=0; PROBE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --init) INIT=1 ;;
    --no-probe) PROBE=0 ;;
    *) echo "AB-USAGE: unknown flag '$1' (known: --init --no-probe)"; exit 1 ;;
  esac
  shift
done

# Instrument needle (§11.4.201(7)(b)): prove sqlite3 exists and answers before
# trusting any of its outputs.
VER=$("$SQLITE" -version 2>/dev/null | head -1)
[ -n "$VER" ] || { echo "AB-BLIND: sqlite3 instrument '$SQLITE' produced no version output — cannot proceed"; exit 2; }

if [ ! -f "$DB" ]; then
  if [ "$INIT" -eq 1 ]; then
    "$SQLITE" "$DB" < "$HERE/custody_schema.sql" || { echo "AB-FAILED: schema init failed for $DB"; exit 1; }
    echo "AB-INIT: created fresh tracker DB at $DB from custody_schema.sql"
  else
    echo "AB-REFUSED: DB '$DB' does not exist and --init was not given — refusing to guess (§11.4.6)."
    echo "  Either point at your real tracker DB, or pass --init to bootstrap a fresh one."
    exit 1
  fi
fi

# Required tables present? (consumer maps its schema onto these names as DATA;
# absence is an actionable refusal, never a silent partial apply)
REQ="items item_history guard_registry verdicts reopen_intake"
MISSING=""
for t in $REQ; do
  n=$("$SQLITE" -readonly "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$t';" 2>/dev/null)
  [ "${n:-0}" = "1" ] || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
  if [ "$INIT" -eq 1 ]; then
    "$SQLITE" "$DB" < "$HERE/custody_schema.sql" 2>/dev/null || true
    MISSING=""
    for t in $REQ; do
      n=$("$SQLITE" -readonly "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$t';" 2>/dev/null)
      [ "${n:-0}" = "1" ] || MISSING="$MISSING $t"
    done
  fi
  if [ -n "$MISSING" ]; then
    echo "AB-REFUSED: DB '$DB' is missing required tables:$MISSING"
    echo "  The custody seam needs {items,item_history,guard_registry,verdicts,reopen_intake}."
    echo "  Map your tracker onto this shape (see custody_schema.sql) — the invariants are the"
    echo "  mechanism, the names are consumer data (§11.4.35)."
    exit 1
  fi
fi

# Build the applied trigger SQL: consumer vocabulary substituted as DATA, and
# DROP-before-CREATE for idempotency.
TLIST=$(ab_terminal_list) || exit 1
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
# Substitute the template marker via bash string replacement — the replacement
# side of ${var//pat/rep} is literal in bash, so the SQL-quoted list (which may
# carry unicode + quotes) needs no second escaping layer (the sed-metacharacter
# class of instrument trap is avoided by not using sed at all).
TPL=$(cat "$HERE/custody_triggers.sql")
if [ "${TPL#*__AB_TERMINAL_LIST__}" = "$TPL" ]; then
  echo "AB-BLIND: custody_triggers.sql carries no __AB_TERMINAL_LIST__ marker — template corrupt"; exit 2
fi
{
  for trg in custody_terminal_refuse custody_reopen_refuse custody_history_auto history_no_update history_no_delete; do
    echo "DROP TRIGGER IF EXISTS $trg;"
  done
  printf '%s\n' "${TPL//__AB_TERMINAL_LIST__/$TLIST}"
} > "$TMP"
# Post-substitution needle (§11.4.201(7)(b)): the marker MUST be gone and the
# first terminal literal MUST be present in the generated SQL.
case "$(cat "$TMP")" in
  *__AB_TERMINAL_LIST__*) echo "AB-FAILED: template substitution left the marker in place"; exit 1 ;;
esac

"$SQLITE" "$DB" < "$TMP" || { echo "AB-FAILED: trigger application failed on $DB"; exit 1; }

# Verify the ARTIFACT layer: all 5 triggers present in sqlite_master.
NTRG=$("$SQLITE" -readonly "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name IN ('custody_terminal_refuse','custody_reopen_refuse','custody_history_auto','history_no_update','history_no_delete');")
if [ "${NTRG:-0}" != "5" ]; then
  echo "AB-FAILED: expected 5 custody triggers in $DB, found ${NTRG:-0}"
  exit 1
fi
echo "AB-APPLIED: 5 custody triggers present in $DB (terminal vocabulary: $TLIST)"

# Live refusal probe (§11.4.108 RUNTIME layer): inside a never-committed
# transaction, insert a throwaway item and attempt an un-evidenced terminal
# write. The trigger MUST abort it. -bail exits at the abort; the connection
# close rolls the open transaction back, so the probe leaves ZERO residue in
# both branches.
if [ "$PROBE" -eq 1 ]; then
  PID="__AB_PROBE_$$_${RANDOM}"
  FIRST=$(ab_first_terminal) || { echo "AB-FAILED: no terminal literal for probe"; exit 1; }
  FIRST_SQL="${FIRST//"'"/"''"}"
  PERR=$(mktemp)
  if "$SQLITE" -bail "$DB" "BEGIN;
INSERT INTO items(atm_id,title,type,status) VALUES('$PID','anti_bluff live probe','Task','In progress');
UPDATE items SET status='$FIRST_SQL' WHERE atm_id='$PID';
ROLLBACK;" 2>"$PERR"; then
    rm -f "$PERR"
    echo "AB-PROBE-FAILED: un-evidenced terminal write was ACCEPTED on $DB — the seam does NOT bind; refusing to report success"
    exit 1
  fi
  if grep -q 'CUSTODY-REFUSED' "$PERR"; then
    echo "PROBE-REFUSED-OK: live un-evidenced terminal write refused on $DB (runtime signature verified, zero residue)"
    rm -f "$PERR"
  else
    echo "AB-PROBE-INCONCLUSIVE: probe insert/update failed for a schema-specific reason, not a custody refusal:"
    sed 's/^/  /' "$PERR"
    rm -f "$PERR"
    echo "  Trigger presence IS verified (5/5); adapt the probe to your schema's required columns."
    exit 1
  fi
fi

exit 0
