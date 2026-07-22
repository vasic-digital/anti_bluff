#!/usr/bin/env bash
# anti_bluff — full test-suite runner.
# Exit 0 only when EVERY suite passes. A missing implementation is a RED suite,
# never a skip (§11.4.3: PASS-by-default is forbidden; §11.4.224: RED first).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITES=(test_needle.sh test_status_custody.sh test_insert_custody.sh test_evidence_class.sh test_out_of_box.sh)
TOTAL=0; RED=0
for s in "${SUITES[@]}"; do
  echo "=============================================="
  echo "SUITE: $s"
  echo "=============================================="
  if bash "$HERE/$s"; then
    echo "SUITE-RESULT: $s GREEN"
  else
    echo "SUITE-RESULT: $s RED"
    RED=$((RED+1))
  fi
  TOTAL=$((TOTAL+1))
done
echo "=============================================="
echo "SUITES: total=$TOTAL red=$RED"
[ "$RED" -eq 0 ]
