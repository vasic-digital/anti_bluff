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
# Substitute the template marker via bash string replacement — no sed, so the
# sed-metacharacter class of instrument trap is avoided, and the SQL-quoted
# list (which may carry unicode + quotes) needs no second escaping layer.
# CAVEAT (verified on bash 5.2.37, §11.4.6): the replacement side of
# ${var//pat/rep} is literal ONLY for values without `&` — on bash >= 5.2
# (`patsub_replacement` on by default) an unquoted `&` in the replacement
# re-expands to the MATCHED pattern, i.e. the marker itself; that case is
# caught fail-closed by the post-substitution check below.
TPL=$(cat "$HERE/custody_triggers.sql")
if [ "${TPL#*__AB_TERMINAL_LIST__}" = "$TPL" ]; then
  echo "AB-BLIND: custody_triggers.sql carries no __AB_TERMINAL_LIST__ marker — template corrupt"; exit 2
fi
{
  for trg in custody_terminal_refuse custody_reopen_refuse custody_history_auto \
             custody_terminal_refuse_ins custody_reopen_refuse_ins custody_history_auto_ins \
             history_no_update history_no_delete; do
    echo "DROP TRIGGER IF EXISTS $trg;"
  done
  printf '%s\n' "${TPL//__AB_TERMINAL_LIST__/$TLIST}"
} > "$TMP"
# Post-substitution needle (§11.4.201(7)(b)): assert ONLY that the marker is
# GONE from the generated SQL — no terminal-literal-present check is performed
# here (the live refusal probes below are the positive evidence). Fail-closed
# cause worth naming (verified on bash 5.2.37): an `&` inside an
# AB_TERMINAL_STATUSES value re-expands, via `patsub_replacement` (bash >= 5.2
# default), to the matched `__AB_TERMINAL_LIST__` marker — the marker then
# survives substitution and this check refuses (AB-FAILED, exit 1), so a
# corrupt vocabulary never reaches the DB.
case "$(cat "$TMP")" in
  *__AB_TERMINAL_LIST__*) echo "AB-FAILED: template substitution left the marker in place"; exit 1 ;;
esac

"$SQLITE" "$DB" < "$TMP" || { echo "AB-FAILED: trigger application failed on $DB"; exit 1; }

# Verify the ARTIFACT layer: all 8 triggers present in sqlite_master
# (3 UPDATE-path + 3 INSERT-path twins + 2 append-only guards).
NTRG=$("$SQLITE" -readonly "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name IN ('custody_terminal_refuse','custody_reopen_refuse','custody_history_auto','custody_terminal_refuse_ins','custody_reopen_refuse_ins','custody_history_auto_ins','history_no_update','history_no_delete');")
if [ "${NTRG:-0}" != "8" ]; then
  echo "AB-FAILED: expected 8 custody triggers in $DB, found ${NTRG:-0}"
  exit 1
fi
echo "AB-APPLIED: 8 custody triggers present in $DB (terminal vocabulary: $TLIST)"

# Live refusal probes (§11.4.108 RUNTIME layer): inside never-committed
# transactions, attempt an un-evidenced terminal write through BOTH status-write
# paths — UPDATE and INSERT. The triggers MUST abort both. -bail exits at the
# abort; the connection close rolls the open transaction back, so each probe
# leaves ZERO residue in both branches.
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
    echo "AB-PROBE-FAILED: un-evidenced terminal UPDATE was ACCEPTED on $DB — the seam does NOT bind; refusing to report success"
    exit 1
  fi
  if grep -q 'CUSTODY-REFUSED' "$PERR"; then
    echo "PROBE-REFUSED-OK: live un-evidenced terminal UPDATE refused on $DB (runtime signature verified, zero residue)"
    rm -f "$PERR"
  else
    echo "AB-PROBE-INCONCLUSIVE: probe insert/update failed for a schema-specific reason, not a custody refusal:"
    sed 's/^/  /' "$PERR"
    rm -f "$PERR"
    echo "  Trigger presence IS verified (8/8); adapt the probe to your schema's required columns."
    exit 1
  fi
  # INSERT-path probe (IMPORTANT-1): a row BORN at a terminal status without the
  # custody chain must be refused identically.
  PID2="__AB_PROBE_INS_$$_${RANDOM}"
  PERR2=$(mktemp)
  if "$SQLITE" -bail "$DB" "BEGIN;
INSERT INTO items(atm_id,title,type,status) VALUES('$PID2','anti_bluff live insert probe','Task','$FIRST_SQL');
ROLLBACK;" 2>"$PERR2"; then
    rm -f "$PERR2"
    echo "AB-PROBE-FAILED: un-evidenced terminal INSERT was ACCEPTED on $DB — the INSERT door is open; refusing to report success"
    exit 1
  fi
  if grep -q 'CUSTODY-REFUSED' "$PERR2"; then
    echo "PROBE-REFUSED-OK: live un-evidenced terminal INSERT refused on $DB (INSERT-path runtime signature verified, zero residue)"
    rm -f "$PERR2"
  else
    echo "AB-PROBE-INCONCLUSIVE: INSERT probe failed for a schema-specific reason, not a custody refusal:"
    sed 's/^/  /' "$PERR2"
    rm -f "$PERR2"
    echo "  Trigger presence IS verified (8/8); adapt the probe to your schema's required columns."
    exit 1
  fi
fi

exit 0
