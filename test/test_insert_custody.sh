#!/usr/bin/env bash
# anti_bluff test — SOL-01 INSERT-path custody (IMPORTANT-1 remediation).
# Written FIRST per §11.4.224/§11.4.115: authored + observed RED on the pre-fix
# artifact (whose custody_triggers.sql carried BEFORE UPDATE triggers ONLY, so a
# raw `INSERT INTO items(...,status='Fixed')` with NO custody chain was ACCEPTED
# with zero audit rows — the PC-1 raw-SQL bypass through the INSERT door), then
# GREEN once the BEFORE/AFTER INSERT trigger twins land. RED transcript:
# test/evidence/INSERT_RED.txt; GREEN: test/evidence/INSERT_GREEN.txt.
#
# Integration test against a REAL temp SQLite DB — no mocks (§11.4.27).
#
# Cases (golden-good + golden-bad + negative-control per §11.4.107(10)):
#   A golden-bad       : raw INSERT at terminal status, NO custody chain -> REFUSED
#                        (on the pre-fix artifact this is ACCEPTED -> the RED)
#   B negative-control : INSERT at terminal status WITH full custody chain -> SUCCEEDS
#                        (§11.4.201(1) false-positive guard — the twin must NOT
#                        block a legitimate insert) + DB writes its own audit row
#   C negative-control : ordinary non-terminal INSERT -> SUCCEEDS untouched
#   D regression-guard : un-evidenced terminal UPDATE still REFUSED (the original
#                        UPDATE seam did not regress)
#   E reopen twin      : INSERT at 'Reopened' without staged intake -> REFUSED;
#                        with staged User intake -> SUCCEEDS with by_actor=User
#   F sweep coherence  : the case-B DB passes the custody sweep (the AFTER INSERT
#                        history twin keeps insert-at-terminal sweep-consistent —
#                        without it a legitimate insert would trip finding C1)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAM="$HERE/../seams/status_custody"
SQLITE="${SQLITE:-sqlite3}"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

missing=0
for f in custody_schema.sql custody_triggers.sql apply_custody.sh custody_sweep.sh; do
  [ -f "$SEAM/$f" ] || { echo "FAIL: missing artifact seams/status_custody/$f"; missing=$((missing+1)); }
done
if [ "$missing" -gt 0 ]; then echo "RESULT: RED ($missing missing artifacts)"; exit 1; fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkdb() { # $1=dbpath
  "$SQLITE" "$1" < "$SEAM/custody_schema.sql"
  bash "$SEAM/apply_custody.sh" "$1" --no-probe >/dev/null
}

# ---- A golden-bad: the PC-1 INSERT-door bypass ------------------------------
DB="$T/insert_bypass.db"; mkdb "$DB"
if "$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('AB-I-001','born terminal, no chain','Bug','Fixed');" 2>"$T/a.err"; then
  bad "A1 raw un-evidenced terminal INSERT was ACCEPTED (the INSERT door is open — PC-1 bypass live)"
else
  grep -q 'CUSTODY-REFUSED' "$T/a.err" && ok "A1 raw un-evidenced terminal INSERT refused with custody message" \
    || bad "A1 refused but without custody message: $(cat "$T/a.err")"
fi
N=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM items WHERE atm_id='AB-I-001';")
[ "$N" = "0" ] && ok "A2 refused INSERT left zero rows (no partial write)" \
  || bad "A2 bypass row landed: items now holds $N row(s) for AB-I-001"

# ---- B negative-control: legitimate insert-at-terminal with full chain ------
DB="$T/insert_good.db"; mkdb "$DB"
"$SQLITE" "$DB" "INSERT INTO guard_registry(guard_id,atm_id,guard_path) VALUES('GI1','AB-I-002','tests/gi1.sh');
INSERT INTO verdicts(guard_id,polarity,exit_code,artifact_fingerprint,evidence_class,evidence_path) VALUES
 ('GI1','RED',1,'fp-broken','runtime','ev/red.log'),
 ('GI1','GREEN',0,'fp-fixed','runtime','ev/green.log');"
if "$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('AB-I-002','migrated closed item','Bug','Fixed');" 2>"$T/b.err"; then
  ok "B1 insert-at-terminal WITH full custody chain succeeds (no §11.4.201(1) false refusal)"
else
  bad "B1 legitimate full-chain terminal INSERT refused: $(cat "$T/b.err")"
fi
H=$("$SQLITE" "$DB" "SELECT COUNT(*) FROM item_history WHERE atm_id='AB-I-002' AND event_type='Fixed';")
[ "$H" = "1" ] && ok "B2 DB wrote its own audit row for the inserted terminal item" \
  || bad "B2 expected 1 auto history row for insert-at-terminal, got $H"

# ---- C negative-control: ordinary open-item INSERT untouched ----------------
if "$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('AB-I-003','ordinary open item','Task','In progress');" 2>"$T/c.err"; then
  ok "C1 ordinary non-terminal INSERT succeeds untouched"
else
  bad "C1 ordinary INSERT refused: $(cat "$T/c.err")"
fi

# ---- D regression-guard: the UPDATE seam still binds ------------------------
if "$SQLITE" "$DB" "UPDATE items SET status='Fixed' WHERE atm_id='AB-I-003';" 2>"$T/d.err"; then
  bad "D1 un-evidenced terminal UPDATE was ACCEPTED (UPDATE seam regressed)"
else
  grep -q 'CUSTODY-REFUSED' "$T/d.err" && ok "D1 un-evidenced terminal UPDATE still refused (UPDATE seam intact)" \
    || bad "D1 refused but without custody message: $(cat "$T/d.err")"
fi

# ---- E reopen twin: INSERT at 'Reopened' -------------------------------------
DB="$T/insert_reopen.db"; mkdb "$DB"
if "$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('AB-I-004','born reopened, unstaged','Bug','Reopened');" 2>"$T/e1.err"; then
  bad "E1 un-staged Reopened INSERT was ACCEPTED"
else
  grep -q 'CUSTODY-REFUSED' "$T/e1.err" && ok "E1 un-staged Reopened INSERT refused" \
    || bad "E1 refused but without custody message: $(cat "$T/e1.err")"
fi
"$SQLITE" "$DB" "INSERT INTO reopen_intake(atm_id,by_actor,reason,evidence_path) VALUES('AB-I-005','User','manual-testing-detected','qa/operator_note.md');"
if "$SQLITE" "$DB" "INSERT INTO items(atm_id,title,type,status) VALUES('AB-I-005','born reopened, staged','Bug','Reopened');" 2>"$T/e2.err"; then
  BY=$("$SQLITE" "$DB" "SELECT by_actor FROM item_history WHERE atm_id='AB-I-005' AND event_type='Reopened';")
  [ "$BY" = "User" ] && ok "E2 staged Reopened INSERT recorded with by_actor=User" \
    || bad "E2 insert accepted but by_actor='$BY' not 'User'"
else
  bad "E2 staged Reopened INSERT refused: $(cat "$T/e2.err")"
fi

# ---- F sweep coherence on the case-B DB -------------------------------------
if bash "$SEAM/custody_sweep.sh" "$T/insert_good.db" >"$T/f.sweep" 2>&1; then
  ok "F1 custody sweep passes the insert-at-terminal DB (history twin keeps C1 coherent)"
else
  bad "F1 sweep flagged the legitimate insert-at-terminal DB: $(cat "$T/f.sweep")"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
