#!/usr/bin/env bash
# anti_bluff test — SOL-01 status custody at the database layer.
# Written FIRST per §11.4.224: RED before seams/status_custody/* exist, GREEN after.
#
# Cases (golden-good + golden-bad + negative-control per §11.4.107(10)):
#   A  golden-good      : full custody chain -> terminal write SUCCEEDS, history auto-row, sweep PASS
#   B  golden-bad-1     : raw un-evidenced UPDATE to terminal -> REFUSED by trigger (raw sqlite3 writer!)
#   C  golden-bad-2     : legacy DB (no triggers), terminal item, zero history -> sweep FAILS naming id
#   D  negative-control : open in-progress item -> sweep MUST NOT flag (§11.4.201(1) false-positive guard)
#   E  operator reopen  : un-staged Reopened REFUSED; staged User attribution SUCCEEDS with by_actor=User
#   F  append-only      : UPDATE on item_history -> REFUSED
#   G  golden-bad-4     : identical RED/GREEN fingerprints -> terminal REFUSED (§11.4.115(F))
#   H  installer        : apply_custody.sh --init creates+triggers a DB, is idempotent, probe proves refusal live
#   I  consumer vocab   : AB_TERMINAL_STATUSES with suffixed literals binds the trigger + sweep to consumer DATA
#   J  sweep needle     : empty items table -> SWEEP-BLIND-OR-EMPTY(2), never PASS (§11.4.201(7)(b))
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAM="$HERE/../seams/status_custody"
SQLITE="${SQLITE:-sqlite3}"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

missing=0
for f in custody_schema.sql custody_triggers.sql custody_sweep.sh apply_custody.sh; do
  [ -f "$SEAM/$f" ] || { echo "FAIL: missing artifact seams/status_custody/$f"; missing=$((missing+1)); }
done
if [ "$missing" -gt 0 ]; then echo "RESULT: RED ($missing missing artifacts)"; exit 1; fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdb() { # $1=dbpath $2=with_triggers(yes|no)
  "$SQLITE" "$1" < "$SEAM/custody_schema.sql"
  if [ "$2" = yes ]; then bash "$SEAM/apply_custody.sh" "$1" --no-probe >/dev/null; fi
}
seed_item() { "$SQLITE" "$1" "INSERT INTO items(atm_id,title,type,status) VALUES('$2','t','Bug','In progress');"; }

# ---- A golden-good --------------------------------------------------------
DB="$T/good.db"; mkdb "$DB" yes; seed_item "$DB" ATM-001
"$SQLITE" "$DB" "INSERT INTO guard_registry(guard_id,atm_id,guard_path) VALUES('G1','ATM-001','tests/guard_ATM-001.sh');
INSERT INTO verdicts(guard_id,polarity,exit_code,artifact_fingerprint,evidence_class,evidence_path) VALUES
 ('G1','RED',1,'fp-broken','runtime','ev/red.log'),
 ('G1','GREEN',0,'fp-fixed','runtime','ev/green.log');"
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='ATM-001';" 2>"$T/a.err"; then
  ok "A1 terminal write with full custody chain succeeds"
else
  bad "A1 terminal write with full custody chain refused: $(cat "$T/a.err")"
fi
H=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM item_history WHERE atm_id='ATM-001' AND event_type='Fixed';")
[ "$H" = "1" ] && ok "A2 history row auto-written by the DB itself" || bad "A2 expected 1 auto history row, got $H"
if bash "$SEAM/custody_sweep.sh" "$DB" >"$T/a.sweep" 2>&1; then
  ok "A3 sweep PASS on custody-clean DB"
else
  bad "A3 sweep failed on clean DB: $(cat "$T/a.sweep")"
fi

# ---- B golden-bad-1: raw bypass write refused ------------------------------
DB="$T/bad1.db"; mkdb "$DB" yes; seed_item "$DB" ATM-002
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='ATM-002';" 2>"$T/b.err"; then
  bad "B1 un-evidenced terminal write via raw sqlite3 was ACCEPTED (seam does not bind)"
else
  grep -q 'CUSTODY-REFUSED' "$T/b.err" && ok "B1 raw un-evidenced terminal write refused with custody message" \
    || bad "B1 refused but without custody message: $(cat "$T/b.err")"
fi

# ---- C golden-bad-2: legacy DB caught by sweep -----------------------------
DB="$T/legacy.db"; mkdb "$DB" no
"$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('ATM-003','t','Bug','Fixed');"
if bash "$SEAM/custody_sweep.sh" "$DB" >"$T/c.sweep" 2>&1; then
  bad "C1 sweep passed a legacy DB holding a zero-history terminal item"
else
  grep -q 'ATM-003' "$T/c.sweep" && ok "C1 sweep FAILs legacy DB and names the offending item" \
    || bad "C1 sweep failed but did not name ATM-003"
fi

# ---- D negative-control: open item never flagged ---------------------------
DB="$T/negctl.db"; mkdb "$DB" yes; seed_item "$DB" ATM-004
if bash "$SEAM/custody_sweep.sh" "$DB" >"$T/d.sweep" 2>&1; then
  ok "D1 sweep does NOT flag an ordinary open item (false-positive guard)"
else
  bad "D1 sweep flagged an open item: $(cat "$T/d.sweep")"
fi

# ---- E reopen attribution --------------------------------------------------
DB="$T/reopen.db"; mkdb "$DB" yes; seed_item "$DB" ATM-005
if "$SQLITE" "$DB" "UPDATE items SET status='Reopened' WHERE atm_id='ATM-005';" 2>"$T/e1.err"; then
  bad "E1 un-staged Reopened flip was ACCEPTED"
else
  grep -q 'CUSTODY-REFUSED' "$T/e1.err" && ok "E1 un-staged Reopened flip refused" \
    || bad "E1 refused without custody message"
fi
"$SQLITE" "$DB" "INSERT INTO reopen_intake(atm_id,by_actor,reason,evidence_path) VALUES('ATM-005','User','manual-testing-detected','qa/operator_note.md');"
if "$SQLITE" "$DB" "UPDATE items SET status='Reopened' WHERE atm_id='ATM-005';" 2>"$T/e2.err"; then
  BY=$("$SQLITE" "$DB" "SELECT by_actor FROM item_history WHERE atm_id='ATM-005' AND event_type='Reopened';")
  [ "$BY" = "User" ] && ok "E2 staged operator reopen recorded with by_actor=User (closes the M6 channel)" \
    || bad "E2 reopen recorded but by_actor='$BY' not 'User'"
else
  bad "E2 staged reopen refused: $(cat "$T/e2.err")"
fi

# ---- F append-only history --------------------------------------------------
if "$SQLITE" "$DB" "UPDATE item_history SET by_actor='AI';" 2>"$T/f.err"; then
  bad "F1 item_history UPDATE was ACCEPTED (audit trail mutable)"
else
  ok "F1 item_history is append-only (UPDATE refused)"
fi

# ---- G golden-bad-4: same-fingerprint pair refused --------------------------
DB="$T/bad4.db"; mkdb "$DB" yes; seed_item "$DB" ATM-006
"$SQLITE" "$DB" "INSERT INTO guard_registry(guard_id,atm_id,guard_path) VALUES('G6','ATM-006','tests/g6.sh');
INSERT INTO verdicts(guard_id,polarity,exit_code,artifact_fingerprint,evidence_class,evidence_path) VALUES
 ('G6','RED',1,'fp-same','runtime','ev/r.log'),
 ('G6','GREEN',0,'fp-same','runtime','ev/g.log');"
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='ATM-006';" 2>"$T/g.err"; then
  bad "G1 terminal write accepted on identical RED/GREEN fingerprints (undeployed fix)"
else
  ok "G1 identical-fingerprint verdict pair refused (§11.4.115(F))"
fi

# ---- H installer: --init + idempotency + live probe -------------------------
DB="$T/installed.db"
if bash "$SEAM/apply_custody.sh" "$DB" --init >"$T/h1.out" 2>&1; then
  NTRG=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name IN ('custody_terminal_refuse','custody_reopen_refuse','custody_history_auto','custody_terminal_refuse_ins','custody_reopen_refuse_ins','custody_history_auto_ins','history_no_update','history_no_delete');")
  [ "$NTRG" = "8" ] && ok "H1 apply_custody --init lands all 8 triggers (UPDATE + INSERT paths)" || bad "H1 expected 8 triggers, got $NTRG"
  grep -q 'PROBE-REFUSED-OK' "$T/h1.out" && ok "H2 live probe proved the refusal fires on THIS db (§11.4.108 runtime signature)" \
    || bad "H2 no live-probe refusal proof in installer output: $(cat "$T/h1.out")"
else
  bad "H1/H2 apply_custody --init failed: $(cat "$T/h1.out")"
fi
if bash "$SEAM/apply_custody.sh" "$DB" >"$T/h3.out" 2>&1; then
  ok "H3 second apply is idempotent (re-apply succeeds)"
else
  bad "H3 re-apply failed: $(cat "$T/h3.out")"
fi
ROWS=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM items;")
[ "$ROWS" = "0" ] && ok "H4 probe left zero residue rows" || bad "H4 probe left $ROWS residue rows"
# H5 fail-closed: no DB path and no --init on a missing file must refuse, never guess
if bash "$SEAM/apply_custody.sh" "$T/does_not_exist.db" >"$T/h5.out" 2>&1; then
  bad "H5 apply_custody accepted a missing DB without --init (guessed instead of failing closed)"
else
  ok "H5 apply_custody fails closed on a missing DB without --init (§11.4.6)"
fi

# ---- I consumer vocabulary as DATA ------------------------------------------
DB="$T/vocab.db"; "$SQLITE" "$DB" < "$SEAM/custody_schema.sql"
AB_TERMINAL_STATUSES='Fixed (→ Fixed.md),Implemented (→ Fixed.md),Completed (→ Fixed.md)' \
  bash "$SEAM/apply_custody.sh" "$DB" --no-probe >"$T/i0.out" 2>&1 || bad "I0 vocab apply failed: $(cat "$T/i0.out")"
seed_item "$DB" ATM-007
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed (→ Fixed.md)' WHERE atm_id='ATM-007';" 2>"$T/i1.err"; then
  bad "I1 un-evidenced suffixed terminal write ACCEPTED (vocabulary not bound)"
else
  grep -q 'CUSTODY-REFUSED' "$T/i1.err" && ok "I1 consumer-vocabulary terminal literal refused un-evidenced" \
    || bad "I1 refused without custody message: $(cat "$T/i1.err")"
fi
DB="$T/vocab_legacy.db"; "$SQLITE" "$DB" < "$SEAM/custody_schema.sql"
"$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('ATM-008','t','Task','Completed (→ Fixed.md)');"
if AB_TERMINAL_STATUSES='Fixed (→ Fixed.md),Implemented (→ Fixed.md),Completed (→ Fixed.md)' \
   bash "$SEAM/custody_sweep.sh" "$DB" >"$T/i2.sweep" 2>&1; then
  bad "I2 sweep passed a legacy DB with a suffixed-vocabulary terminal item"
else
  grep -q 'ATM-008' "$T/i2.sweep" && ok "I2 sweep honors consumer vocabulary and names the offender" \
    || bad "I2 sweep failed but did not name ATM-008"
fi

# ---- J sweep control needle --------------------------------------------------
DB="$T/empty.db"; "$SQLITE" "$DB" < "$SEAM/custody_schema.sql"
bash "$SEAM/custody_sweep.sh" "$DB" >"$T/j.sweep" 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'SWEEP-BLIND' "$T/j.sweep"; then
  ok "J1 empty items table -> SWEEP-BLIND-OR-EMPTY(2), never a PASS (§11.4.201(7)(b))"
else
  bad "J1 expected blind(2) on empty table, got rc=$rc: $(cat "$T/j.sweep")"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
