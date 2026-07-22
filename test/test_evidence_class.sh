#!/usr/bin/env bash
# anti_bluff test — SOL-04 evidence-class-at-closure enforcement.
# Written FIRST per §11.4.224: RED before seams/evidence_class/evidence_class_check.sh
# exists, GREEN after.
#
# The discriminator this seam mechanizes (measured, no counter-case in any corpus):
# every fix closed on an on-target RED->GREEN flip held (0 reopens); every fix
# closed at source-green bounced. So: a closure's evidence must be of the CLASS of
# the defect's LAYER, proven by machine fields — never by a label.
#
# Cases:
#   A golden-good      : user-visible defect + true runtime evidence -> 0
#   B golden-bad-1     : user-visible defect + grep transcript labelled runtime -> 1 WRONG-LAYER
#   C golden-bad-2     : runtime label without machine fields -> 1 SHAPE-INCOMPLETE
#   D negative-control : source defect + source evidence -> 0 (no §11.4.201(1) false refusal)
#   E blind            : unreadable evidence file -> 2, never accepted
#   F golden-bad-3     : user-visible defect + artifact-class evidence -> 1 CLASS-INSUFFICIENT
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../seams/evidence_class/evidence_class_check.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$CHECK" ]; then
  echo "FAIL: missing artifact seams/evidence_class/evidence_class_check.sh"
  echo "RESULT: RED (implementation absent)"
  exit 1
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---- A golden-good ---------------------------------------------------------
cat > "$T/runtime.ev" <<'EOF'
EVIDENCE-CLASS: runtime
TARGET_FINGERPRINT: build-2026-07-23-abcdef
RUNTIME_OBSERVABLE: dumpsys media.decoder frame-advance 1204->1381 over 5s window
EOF
if bash "$CHECK" user-visible "$T/runtime.ev" >"$T/a.out" 2>&1; then
  ok "A1 user-visible defect + true runtime evidence accepted"
else
  bad "A1 true runtime evidence refused: $(cat "$T/a.out")"
fi

# ---- B golden-bad-1: the PC-8 echo (grep wearing a runtime label) ----------
cat > "$T/echo.ev" <<'EOF'
EVIDENCE-CLASS: runtime
TARGET_FINGERPRINT: build-2026-07-23-abcdef
RUNTIME_OBSERVABLE: grep: 5 hits for renderFrame in ExamplePlayerService.java
EOF
if bash "$CHECK" user-visible "$T/echo.ev" >"$T/b.out" 2>&1; then
  bad "B1 grep transcript wearing a runtime label was ACCEPTED (the five-greps-for-a-pixel-defect bluff)"
else
  grep -q 'WRONG-LAYER' "$T/b.out" && ok "B1 grep-echo refused as WRONG-LAYER" \
    || bad "B1 refused but not as WRONG-LAYER: $(cat "$T/b.out")"
fi

# ---- C golden-bad-2: label without machine fields --------------------------
cat > "$T/bare.ev" <<'EOF'
EVIDENCE-CLASS: runtime
EOF
if bash "$CHECK" user-visible "$T/bare.ev" >"$T/c.out" 2>&1; then
  bad "C1 fieldless runtime label was ACCEPTED"
else
  grep -q 'SHAPE-INCOMPLETE' "$T/c.out" && ok "C1 fieldless label refused as SHAPE-INCOMPLETE" \
    || bad "C1 refused but not as SHAPE-INCOMPLETE: $(cat "$T/c.out")"
fi

# ---- D negative-control: source-on-source is legitimate --------------------
cat > "$T/source.ev" <<'EOF'
EVIDENCE-CLASS: source
SOURCE_REF: commit abc1234 file scripts/lib/example.sh line 42
EOF
if bash "$CHECK" source "$T/source.ev" >"$T/d.out" 2>&1; then
  ok "D1 source-layer defect closed on source evidence (no false refusal)"
else
  bad "D1 legitimate source-layer closure refused: $(cat "$T/d.out")"
fi

# ---- E blind: unreadable evidence ------------------------------------------
bash "$CHECK" user-visible "$T/nonexistent.ev" >"$T/e.out" 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then
  ok "E1 unreadable evidence -> BLIND(2), never accepted"
else
  bad "E1 expected BLIND(2), got rc=$rc: $(cat "$T/e.out")"
fi

# ---- F golden-bad-3: class below the layer floor ---------------------------
cat > "$T/artifact.ev" <<'EOF'
EVIDENCE-CLASS: artifact
ARTIFACT_PATH: out/target/product/x/system.img
ARTIFACT_SHA256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
EOF
if bash "$CHECK" user-visible "$T/artifact.ev" >"$T/f.out" 2>&1; then
  bad "F1 artifact-class evidence accepted for a user-visible defect"
else
  grep -q 'CLASS-INSUFFICIENT' "$T/f.out" && ok "F1 artifact evidence refused as CLASS-INSUFFICIENT for a user-visible defect" \
    || bad "F1 refused but not as CLASS-INSUFFICIENT: $(cat "$T/f.out")"
fi

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
