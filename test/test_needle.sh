#!/usr/bin/env bash
# anti_bluff test — SOL-03 needled measurement primitive (lib/needle.sh).
# Written FIRST per §11.4.224: this test MUST be RED (exit 1) before lib/needle.sh
# exists and GREEN after. Golden-good + golden-bad + negative-control per
# §11.4.107(10) — a validator that passes its own golden-bad is the bluff this
# submodule exists to kill.
#
# Contract under test (lib/needle.sh):
#   nq_absent <file> <query-ere> <needle-ere>
#     0 CERTIFIED-ABSENT | 1 PRESENT (+ sample lines) | 2 INSTRUMENT-BLIND | 3 NEEDLE-CLASS-MISMATCH
#   nq_stream_contains <producer...> -- <ere>
#     0 present | 1 absent | 2 blind — consumer reads producer to EOF (SIGPIPE-immune)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib/needle.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$LIB" ]; then
  echo "FAIL: missing artifact lib/needle.sh"
  echo "RESULT: RED (implementation absent)"
  exit 1
fi
# shellcheck source=/dev/null
. "$LIB"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Fixture: a real corpus with a present token, a prose CARRIER of another token,
# and a line-anchored needle.
cat > "$T/corpus.txt" <<'EOF'
NEEDLE_LINE: present at line start
some prose that mentions GATE_X: only as a carrier, mid-line
REAL_TOKEN present here
EOF

# ---- A golden-good: present token reported PRESENT with the lines ----------
out=$(nq_absent "$T/corpus.txt" 'REAL_TOKEN' 'NEEDLE_LINE'); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q 'REAL_TOKEN'; then
  ok "A1 present token -> PRESENT(1) carrying the matching lines (MU-6: lines, not just a count)"
else
  bad "A1 expected PRESENT(1)+lines, got rc=$rc out=$out"
fi

# ---- B golden-good: absent token certified only via a sighted needle -------
out=$(nq_absent "$T/corpus.txt" 'TOKEN_THAT_IS_NOT_THERE' 'NEEDLE_LINE'); rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'CERTIFIED-ABSENT'; then
  ok "B1 absent token -> CERTIFIED-ABSENT(0) with the needle sighted through the same path"
else
  bad "B1 expected CERTIFIED-ABSENT(0), got rc=$rc out=$out"
fi

# ---- C golden-bad: a BLIND instrument must never certify absence -----------
# Inject a see-nothing grep. The primitive MUST return 2 INSTRUMENT-BLIND,
# never 0 — a blind instrument and a clean artifact return the identical quiet
# zero, and only the needle distinguishes them (§11.4.201(7)(b)).
cat > "$T/blindgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$T/blindgrep"
out=$(NQ_GREP="$T/blindgrep" nq_absent "$T/corpus.txt" 'TOKEN_THAT_IS_NOT_THERE' 'NEEDLE_LINE'); rc=$?
if [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q 'INSTRUMENT-BLIND'; then
  ok "C1 blind instrument -> INSTRUMENT-BLIND(2), never CERTIFIED-ABSENT (golden-bad caught)"
else
  bad "C1 blind instrument was not detected: rc=$rc out=$out"
fi

# ---- D golden-bad: featureless needle refused on a feature-bearing query ---
# Query uses alternation; a bare-literal needle sails through the dialect layer
# that could be eating the query, so it certifies nothing.
out=$(nq_absent "$T/corpus.txt" 'ABSENT_A|ABSENT_B' 'NEEDLE_LINE'); rc=$?
if [ "$rc" -eq 3 ] && printf '%s\n' "$out" | grep -q 'NEEDLE-CLASS-MISMATCH'; then
  ok "D1 alternation query + literal needle -> NEEDLE-CLASS-MISMATCH(3) refused"
else
  bad "D1 class-mismatched needle not refused: rc=$rc out=$out"
fi

# ---- E golden-good: class-matched needle certifies the same query ----------
out=$(nq_absent "$T/corpus.txt" 'ABSENT_A|ABSENT_B' 'NEEDLE_LINE|REAL_TOKEN'); rc=$?
if [ "$rc" -eq 0 ]; then
  ok "E1 same query certified once the needle carries the alternation feature class"
else
  bad "E1 class-matched needle failed to certify: rc=$rc out=$out"
fi

# ---- F negative-control: a carrier does not false-match an anchored query --
# 'GATE_X:' exists mid-line as prose; the STRUCTURE-anchored query '^GATE_X:'
# must not match it (§11.4.201(7)(a) carrier-vs-thing), and the anchored needle
# '^NEEDLE_LINE:' proves the anchored path can see.
out=$(nq_absent "$T/corpus.txt" '^GATE_X:' '^NEEDLE_LINE:'); rc=$?
if [ "$rc" -eq 0 ]; then
  ok "F1 mid-line carrier does not satisfy a line-anchored query (carrier-vs-thing negative control)"
else
  bad "F1 carrier false-matched or anchored path blind: rc=$rc out=$out"
fi

# ---- G stream presence is SIGPIPE-immune under pipefail --------------------
# Producer emits the token on line 1 then >2 MB more. Under `set -o pipefail`
# an early-exit consumer (grep -q) can read a PRESENT literal as ABSENT (the
# measured 400/400 false-absent class). The primitive reads to EOF by
# construction and MUST return present.
head -c 2097152 /dev/zero | tr '\0' 'x' > "$T/payload.txt"
{ echo 'THE_TOKEN_ON_LINE_ONE'; cat "$T/payload.txt"; } > "$T/bigstream.txt"
set -o pipefail
raw_rc=0
cat "$T/bigstream.txt" | grep -q 'THE_TOKEN_ON_LINE_ONE' || raw_rc=$?
set +o pipefail
echo "INFO: raw 'cat | grep -q' under pipefail on 2MB payload returned rc=$raw_rc (host-dependent hazard demo; 0 would mean not reproduced here)"
if nq_stream_contains cat "$T/bigstream.txt" -- 'THE_TOKEN_ON_LINE_ONE' >/dev/null; then
  ok "G1 nq_stream_contains reads producer to EOF -> PRESENT on the same payload (SIGPIPE class closed by construction)"
else
  bad "G1 nq_stream_contains failed to see a present token on a large stream"
fi

# ---- H stream absent + blind producer --------------------------------------
if out=$(nq_stream_contains cat "$T/bigstream.txt" -- 'TOKEN_NOWHERE'); then
  bad "H1 absent stream token reported present"
else
  rc=$?
  [ "$rc" -eq 1 ] && ok "H1 absent stream token -> absent(1)" || bad "H1 expected 1, got $rc"
fi
if out=$(nq_stream_contains false -- 'ANYTHING'); then
  bad "H2 failed producer reported a verdict"
else
  rc=$?
  [ "$rc" -eq 2 ] && ok "H2 failed producer -> INSTRUMENT-BLIND(2), never a verdict" || bad "H2 expected 2, got $rc"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
