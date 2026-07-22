#!/usr/bin/env bash
# anti_bluff SOL-01 Seam B — full-table custody sweep (build-seam gate).
# Catches what triggers cannot: LEGACY databases created before the triggers
# existed, or databases whose triggers were dropped. A diff-scoped check misses
# raw writes that bypassed the sanctioned tool (§11.4.146(D3): Seam B is a
# FULL-TABLE sweep by design).
#
# Usage : custody_sweep.sh <db-path> [--require-triggers]
#           --require-triggers  additionally FAIL when the 5 custody triggers are
#                               absent (for DBs DECLARED triggered; default off so
#                               legacy DBs are legitimately sweepable without a
#                               §11.4.201(1) false positive)
# Env   : AB_TERMINAL_STATUSES  consumer terminal vocabulary as DATA
#         SQLITE                sqlite3 binary (default sqlite3)
# Exit  : 0 = custody-clean   1 = findings (each named)   2 = blind/empty instrument
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLITE="${SQLITE:-sqlite3}"
# shellcheck source=/dev/null
. "$HERE/ab_sql_lib.sh"

DB="${1:?usage: custody_sweep.sh <db-path> [--require-triggers]}"; shift
REQUIRE_TRIGGERS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --require-triggers) REQUIRE_TRIGGERS=1 ;;
    *) echo "AB-USAGE: unknown flag '$1' (known: --require-triggers)"; exit 1 ;;
  esac
  shift
done

TLIST=$(ab_terminal_list) || exit 2
q() { "$SQLITE" -readonly "$DB" "$1"; }

# Control needle (§11.4.201(7)(b)): prove the instrument can see rows at all
# before reporting any zero. An empty items table is BLIND-OR-EMPTY, never PASS.
TOTAL=$(q "SELECT COUNT(*) FROM items;") || { echo "SWEEP-BLIND: cannot read items table in $DB"; exit 2; }
if [ "${TOTAL:-0}" -eq 0 ]; then
  echo "SWEEP-BLIND-OR-EMPTY: items table has 0 rows — a zero here certifies nothing"
  exit 2
fi

FINDINGS=0
report() { echo "CUSTODY-FINDING[$1]: $2"; FINDINGS=$((FINDINGS+1)); }

# C0 (opt-in) — a DB declared triggered must still carry its triggers
# (3 UPDATE-path + 3 INSERT-path twins + 2 append-only guards = 8).
if [ "$REQUIRE_TRIGGERS" -eq 1 ]; then
  NTRG=$(q "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name IN ('custody_terminal_refuse','custody_reopen_refuse','custody_history_auto','custody_terminal_refuse_ins','custody_reopen_refuse_ins','custody_history_auto_ins','history_no_update','history_no_delete');")
  [ "${NTRG:-0}" = "8" ] || report C0 "DB declared triggered but carries ${NTRG:-0}/8 custody triggers (DROP TRIGGER detected)"
fi

# C1 — terminal-status items with ZERO history rows (the measured 48% class).
while IFS='|' read -r id st; do
  [ -n "$id" ] && report C1 "item $id status='$st' has zero item_history rows"
done < <(q "SELECT i.atm_id, i.status FROM items i
            WHERE i.status IN ($TLIST)
              AND NOT EXISTS (SELECT 1 FROM item_history h WHERE h.atm_id = i.atm_id);")

# C2 — Reopened items with no Reopened event.
while IFS='|' read -r id; do
  [ -n "$id" ] && report C2 "item $id is Reopened with no Reopened event"
done < <(q "SELECT i.atm_id FROM items i
            WHERE i.status = 'Reopened'
              AND NOT EXISTS (SELECT 1 FROM item_history h WHERE h.atm_id = i.atm_id AND h.event_type = 'Reopened');")

# C3 — impossible sequences: reopen events with zero terminal events (you cannot
#      reopen what was never closed — proves ledger bypass).
while IFS='|' read -r id; do
  [ -n "$id" ] && report C3 "item $id has Reopened events but zero terminal events (ledger bypassed)"
done < <(q "SELECT DISTINCT h.atm_id FROM item_history h
            WHERE h.event_type = 'Reopened'
              AND NOT EXISTS (SELECT 1 FROM item_history t WHERE t.atm_id = h.atm_id
                              AND t.event_type IN ($TLIST));")

# C4 — terminal-status items with no valid verdict-pair custody (the measured
#      92.5%-unguarded-done class).
while IFS='|' read -r id st; do
  [ -n "$id" ] && report C4 "item $id status='$st' has no RED/GREEN verdict pair on distinct fingerprints"
done < <(q "SELECT i.atm_id, i.status FROM items i
            WHERE i.status IN ($TLIST)
              AND NOT EXISTS (
                SELECT 1 FROM guard_registry g
                JOIN verdicts red   ON red.guard_id = g.guard_id AND red.polarity='RED'   AND red.exit_code <> 0
                JOIN verdicts green ON green.guard_id = g.guard_id AND green.polarity='GREEN' AND green.exit_code = 0
                 AND green.artifact_fingerprint <> red.artifact_fingerprint
                WHERE g.atm_id = i.atm_id);")

echo "SWEEP: items=$TOTAL findings=$FINDINGS"
[ "$FINDINGS" -eq 0 ]
