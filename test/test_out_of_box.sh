#!/usr/bin/env bash
# anti_bluff test — OUT-OF-THE-BOX hermetic proof.
# Written FIRST per §11.4.224. This is the anti-bluff proof of the operator's
# out-of-box requirement: "Incorporated solution MUST WORK out of the box with any
# project which incorporates constitution Submodule as soon as they fetch and pull
# the changes and Submodule is cloned."
#
# The test does what a consumer does — nothing else:
#   1. `git clone` this repository's COMMITTED state into a throwaway "consumer
#      project" (hermetic: local clone, no network; only committed files travel,
#      exactly as they would through the constitution submodule).
#   2. Run the documented one-command install against a consumer DB.
#   3. Prove the seam BINDS: a raw un-evidenced terminal write via plain sqlite3
#      is REFUSED; a full-custody write succeeds with an auto history row.
#   4. Prove the sibling instruments run from the clone: custody sweep +
#      evidence-class checker + needle library.
#
# An uncommitted implementation file cannot pass this test — the clone will not
# contain it. That is deliberate (§11.4.108 SOURCE vs ARTIFACT: the shipped tree,
# not the working tree, is what consumers get).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SQLITE="${SQLITE:-sqlite3}"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if ! git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  echo "FAIL: repository has no commits yet — out-of-box cannot be proven on an uncommitted tree"
  echo "RESULT: RED"
  exit 1
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
CONSUMER="$T/consumer_project"
mkdir -p "$CONSUMER"

# ---- 1. clone the committed tree (what a consumer receives) -----------------
if git clone -q "$ROOT" "$CONSUMER/anti_bluff" 2>"$T/clone.err"; then
  ok "OB1 committed tree clones into a throwaway consumer project"
else
  bad "OB1 clone failed: $(cat "$T/clone.err")"; echo "RESULT: PASS=$PASS FAIL=$FAIL"; exit 1
fi
AB="$CONSUMER/anti_bluff"

# ---- 2. one-command install against a consumer DB ---------------------------
if bash "$AB/install.sh" --db "$CONSUMER/tracker.db" --init >"$T/install.out" 2>&1; then
  ok "OB2 one-command install succeeds from the clone"
else
  bad "OB2 install failed: $(cat "$T/install.out")"; echo "RESULT: PASS=$PASS FAIL=$FAIL"; exit 1
fi
grep -q 'PROBE-REFUSED-OK' "$T/install.out" && ok "OB3 installer proved the refusal live on the consumer DB" \
  || bad "OB3 installer output carries no live refusal proof: $(cat "$T/install.out")"

# ---- 3. the seam binds against a RAW writer ---------------------------------
"$SQLITE" "$CONSUMER/tracker.db" "INSERT INTO items(atm_id,title,type,status) VALUES('CONS-001','consumer item','Bug','In progress');"
if "$SQLITE" "$CONSUMER/tracker.db" "UPDATE items SET status='Fixed' WHERE atm_id='CONS-001';" 2>"$T/raw.err"; then
  bad "OB4 raw un-evidenced terminal write ACCEPTED on the consumer DB (seam does not bind out of the box)"
else
  grep -q 'CUSTODY-REFUSED' "$T/raw.err" && ok "OB4 raw un-evidenced terminal write REFUSED on the consumer DB" \
    || bad "OB4 refused without custody message: $(cat "$T/raw.err")"
fi
"$SQLITE" "$CONSUMER/tracker.db" "INSERT INTO guard_registry(guard_id,atm_id,guard_path) VALUES('CG1','CONS-001','tests/cg1.sh');
INSERT INTO verdicts(guard_id,polarity,exit_code,artifact_fingerprint,evidence_class,evidence_path) VALUES
 ('CG1','RED',1,'fp-old','runtime','ev/red.log'),
 ('CG1','GREEN',0,'fp-new','runtime','ev/green.log');"
if "$SQLITE" "$CONSUMER/tracker.db" "UPDATE items SET status='Fixed' WHERE atm_id='CONS-001';" 2>"$T/full.err"; then
  H=$("$SQLITE" "$CONSUMER/tracker.db" "SELECT COUNT(*) FROM item_history WHERE atm_id='CONS-001' AND event_type='Fixed';")
  [ "$H" = "1" ] && ok "OB5 full-custody write succeeds + DB wrote its own audit row" \
    || bad "OB5 write succeeded but auto history rows = $H"
else
  bad "OB5 full-custody write refused: $(cat "$T/full.err")"
fi

# ---- 4. sibling instruments run from the clone ------------------------------
if bash "$AB/seams/status_custody/custody_sweep.sh" "$CONSUMER/tracker.db" >"$T/sweep.out" 2>&1; then
  ok "OB6 custody sweep runs from the clone and passes the clean consumer DB"
else
  bad "OB6 sweep failed on the clean consumer DB: $(cat "$T/sweep.out")"
fi
cat > "$T/echo.ev" <<'EOF'
EVIDENCE-CLASS: runtime
TARGET_FINGERPRINT: fp
RUNTIME_OBSERVABLE: grep: 3 hits in Foo.java
EOF
if bash "$AB/seams/evidence_class/evidence_class_check.sh" user-visible "$T/echo.ev" >"$T/ec.out" 2>&1; then
  bad "OB7 evidence-class checker from the clone accepted a grep-echo"
else
  ok "OB7 evidence-class checker from the clone refuses a grep-echo"
fi
# needle library loads and certifies through the clone
if out=$(. "$AB/lib/needle.sh" && nq_absent "$AB/README.md" 'TOKEN_SURELY_ABSENT_12345' 'anti_bluff'); then
  ok "OB8 needle library certifies an absence through the clone (needle sighted in README)"
else
  bad "OB8 needle library failed through the clone: $out"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
