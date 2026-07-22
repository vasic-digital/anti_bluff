#!/usr/bin/env bash
# anti_bluff — §11.4.224(E) bash line-coverage measurement (IMPORTANT-2 remediation).
#
# Mechanism (the constitution's proven zero-tooling bash instrument): run the full
# test suite with xtrace propagated into EVERY child bash via env SHELLOPTS=xtrace,
# trace routed to a dedicated fd via BASH_XTRACEFD (so test stdout/stderr captures
# are never contaminated), PS4 stamping ${BASH_SOURCE}:${LINENO} per executed
# command. Coverage = unique executed lines ÷ executable (non-blank, non-comment)
# lines, per tracked *.sh file, attributed by basename (the out-of-box suite
# executes byte-identical CLONE copies of the committed tree — same basenames,
# same line numbers; measure on a COMMITTED tree only).
#
# HONEST LIMITS (§11.4.6 — recorded, not hidden):
#   - LINE coverage, NOT branch coverage (a one-line if/else counts covered with
#     one branch never taken).
#   - `set +x` regions and traps are unaccounted.
#   - Block terminators (fi/done/esac/}/heredoc bodies/EOF markers) count in the
#     denominator but can never appear in a trace — every figure is therefore a
#     conservative LOWER BOUND that structurally undercounts.
#   - Requires a committed tree (clone-copy attribution); refuses otherwise.
#   - kcov/bashcov/bats-class instruments: probed ABSENT on this host (recorded
#     in the captured report); branch-capable measurement is OWED (README §5).
#
# Control needle (§11.4.201(7)(b)): before ANY figure is reported, the trace MUST
# carry COV lines attributed to run_all.sh — a file this very invocation provably
# executed. No needle -> INSTRUMENT-BLIND(2), never a report.
#
# Exclusions: §11.4.224(E) fence — ONLY via the checked-in
# test/coverage_exclusions.txt, each entry printed as an honest gap, first-party
# entries tracked as §11.4.197 items in README §5.
#
# Usage : bash test/coverage_report.sh
# Exit  : 0 report produced | 1 suite failed under trace | 2 instrument blind
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if ! git -C "$ROOT" diff --quiet HEAD -- 2>/dev/null || ! git -C "$ROOT" diff --cached --quiet 2>/dev/null; then
  echo "INSTRUMENT-BLIND: working tree differs from HEAD — clone-copy line attribution would be wrong; commit first"
  exit 2
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TRACE="$T/cov.trace"; SUITE_LOG="$T/suite.log"

# Traced full-suite run. fd 9 is inherited by every child bash; SHELLOPTS=xtrace
# from the environment switches xtrace on in each of them at startup.
env SHELLOPTS=xtrace BASH_XTRACEFD=9 PS4='+COV:${BASH_SOURCE}:${LINENO}:' \
  bash "$ROOT/test/run_all.sh" >"$SUITE_LOG" 2>&1 9>>"$TRACE"
SUITE_RC=$?

# Control needle: the instrument must have SEEN the file it just executed.
if ! grep -Eq '^\++COV:[^:]*run_all\.sh:[0-9]+:' "$TRACE"; then
  echo "INSTRUMENT-BLIND: trace carries no COV lines for run_all.sh (known-executed) — the zero says NOTHING; no report"
  exit 2
fi

# Parse trace -> "basename:line" unique pairs.
sed -nE 's/^\++COV:([^:]+):([0-9]+):.*/\1:\2/p' "$TRACE" \
  | awk -F: '{n=split($1,a,"/"); print a[n]":"$2}' | sort -u > "$T/hits"

EXCL="$HERE/coverage_exclusions.txt"
is_excluded() { [ -f "$EXCL" ] && grep -Eq "^$1([[:space:]]|$)" "$EXCL"; }

echo "COVERAGE (bash line-trace LOWER BOUND, §11.4.224(E)) — anti_bluff @ $(git -C "$ROOT" rev-parse --short HEAD) $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "suite exit under trace: $SUITE_RC (suite tail: $(tail -1 "$SUITE_LOG"))"
echo "---------------------------------------------------------------"
TOT_EXEC=0; TOT_ABLE=0
while IFS= read -r f; do
  if is_excluded "$f"; then
    echo "EXCLUDED (honest gap, §11.4.224(E) fence): $f — $(grep -E "^$f" "$EXCL" | cut -d' ' -f2- )"
    continue
  fi
  bn="${f##*/}"
  able=$(grep -cvE '^[[:space:]]*(#|$)' "$ROOT/$f")
  exec_n=$(awk -F: -v b="$bn" '$1==b' "$T/hits" | wc -l)
  [ "$exec_n" -gt "$able" ] && exec_n="$able"
  pct=$(( able > 0 ? exec_n * 100 / able : 0 ))
  printf '%-45s %4d/%-4d = %3d%%\n' "$f" "$exec_n" "$able" "$pct"
  TOT_EXEC=$((TOT_EXEC + exec_n)); TOT_ABLE=$((TOT_ABLE + able))
done < <(git -C "$ROOT" ls-files '*.sh' | sort)
echo "---------------------------------------------------------------"
printf 'TOTAL (measured corpus)                       %4d/%-4d = %3d%%\n' \
  "$TOT_EXEC" "$TOT_ABLE" "$(( TOT_ABLE > 0 ? TOT_EXEC * 100 / TOT_ABLE : 0 ))"
echo "Go sources: $(git -C "$ROOT" ls-files '*.go' | wc -l) — 'go test -cover' NOT APPLICABLE in this slice (honest §11.4.3 skip)"
echo "kcov present: $(command -v kcov >/dev/null && echo yes || echo no); bashcov: $(command -v bashcov >/dev/null && echo yes || echo no); bats: $(command -v bats >/dev/null && echo yes || echo no)"
echo "HONEST LIMITS: line-not-branch; set+x/traps unaccounted; block terminators"
echo "in denominator but untraceable -> every figure is a conservative lower bound."
[ "$SUITE_RC" -eq 0 ]
