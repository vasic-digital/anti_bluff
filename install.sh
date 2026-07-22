#!/usr/bin/env bash
# anti_bluff — one-command consumer install.
#
# Purpose : Wire the anti_bluff seams into a consuming project. The submodule is
#           project-agnostic (§11.4.28/§11.4.177): every project-specific value
#           (DB path, terminal-status vocabulary) is supplied HERE as data —
#           nothing is guessed (§11.4.6), so with no arguments this script
#           prints usage and refuses.
# Usage   :
#   install.sh --db <tracker.db> [--init] [--no-probe]
#       Apply the SOL-01 status-custody seam to the consumer's SQLite tracker.
#       After this, a terminal status without a registered guard + RED/GREEN
#       verdict pair on distinct artifact fingerprints is UNWRITABLE — for every
#       writer, including raw sqlite3.
#   install.sh --self-test
#       Run the bundled anti-bluff suite (golden-good + golden-bad +
#       negative-control per mechanism, §11.4.107(10)) including the hermetic
#       out-of-the-box test.
# Env     : AB_TERMINAL_STATUSES  consumer terminal vocabulary (comma-separated;
#                                 default Fixed,Implemented,Completed)
#           SQLITE                sqlite3 binary (default sqlite3)
# Exit    : 0 installed + live-verified | 1 refused/failed | 2 blind instrument
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLITE="${SQLITE:-sqlite3}"

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
}

[ $# -gt 0 ] || { usage; echo; echo "AB-REFUSED: no arguments — anti_bluff never guesses a project's paths (§11.4.6)"; exit 1; }

MODE=""; DB=""; PASSTHRU=()
while [ $# -gt 0 ]; do
  case "$1" in
    --db) MODE="db"; DB="${2:?--db requires a path}"; shift ;;
    --init|--no-probe) PASSTHRU+=("$1") ;;
    --self-test) MODE="selftest" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "AB-USAGE: unknown argument '$1'"; usage; exit 1 ;;
  esac
  shift
done

case "$MODE" in
  selftest)
    exec bash "$HERE/test/run_all.sh"
    ;;
  db)
    # Instrument needle before trusting anything (§11.4.201(7)(b)).
    VER=$("$SQLITE" -version 2>/dev/null | head -1)
    [ -n "$VER" ] || { echo "AB-BLIND: sqlite3 instrument '$SQLITE' produced no version output"; exit 2; }
    echo "AB-INSTRUMENT: $SQLITE = $VER"
    bash "$HERE/seams/status_custody/apply_custody.sh" "$DB" ${PASSTHRU[@]+"${PASSTHRU[@]}"} || exit $?
    cat <<EOF

anti_bluff status-custody seam is LIVE on: $DB
Wire the remaining seams into your gates (consumer data, your paths):

  # build seam — full-table custody sweep (add to your pre-build suite):
  bash $HERE/seams/status_custody/custody_sweep.sh "$DB" --require-triggers

  # status-write seam — evidence-class check (call before any closure):
  bash $HERE/seams/evidence_class/evidence_class_check.sh <defect-layer> <evidence-file>

  # every measurement — needled primitives (source in your scripts):
  . $HERE/lib/needle.sh   # nq_absent / nq_count / nq_stream_contains
EOF
    ;;
  *)
    usage; exit 1 ;;
esac
