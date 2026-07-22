# anti_bluff — mechanical anti-bluff seams for any Helix-constitution project

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-07-23 |
| Status | active — first coherent slice (SOL-03 + SOL-01 + SOL-04) + Phase-4 review remediation (INSERT-path custody twins, needled stream absence, coverage baseline); remaining mechanisms OWED (see §5) |
| Upstreams | `git@github.com:vasic-digital/anti_bluff.git` + `git@gitlab.com:vasic-digital/anti_bluff.git` |
| Consumed as | depth-1 reusable engine under `constitution/submodules/anti_bluff/` (§11.4.28(C) carve-out) |
| Classification | universal (§11.4.17) — ZERO project literals; every project-specific value is consumer DATA |

## 1. Why this exists (the design law)

Four independent evidence lines (internal forensics across 576 tracked items; a
76-source external literature review; two cross-project corpora) converged on one
sentence:

> **Prose does not bind; seams do.** What predicts whether a fix holds is the
> EVIDENCE CLASS AT CLOSURE (runtime vs source) under real DETECTION PRESSURE.

Measured: 95% of done-claiming items had no registered guard, and an operator
sample of 6 done-claimers found 6/6 broken; every fix closed on an on-target
RED→GREEN flip held (zero reopens) while every fix confirmed at source-green
bounced. This repository ships the proven mechanisms as **executable seams that
REFUSE on the real condition** — never as rules an agent consults.

Full research + POCs (65/65 green, RED-first): the constitution submodule's
`docs/research/quality/` tree (`ROOT_CAUSE_ANALYSIS.md`, `solutions/SOL-*.md`,
`solutions/poc/`).

## 2. Quick start (out of the box)

From a project that has the constitution submodule (after `git submodule update
--init --recursive`):

```bash
# Wire the status-custody seam into YOUR tracker DB (path = consumer data):
bash constitution/submodules/anti_bluff/install.sh --db docs/workable_items.db

# Custom terminal vocabulary (consumer data, §11.4.35):
AB_TERMINAL_STATUSES='Fixed (→ Fixed.md),Implemented (→ Fixed.md),Completed (→ Fixed.md)' \
  bash constitution/submodules/anti_bluff/install.sh --db docs/workable_items.db

# Prove everything on your host (hermetic; includes a real clone + install + refusal):
bash constitution/submodules/anti_bluff/install.sh --self-test
```

`install.sh` refuses to run with no arguments — anti_bluff never guesses a
project's paths (§11.4.6). Requirements: `bash` + `sqlite3` (both probed with a
control needle before use).

## 3. The seams (shipped in this slice)

### 3.1 `lib/needle.sh` — the needled measurement primitive (SOL-03, §11.4.201(6)(7)(8))

The meta-mechanism protecting every other mechanism's own measurements. No code
path can emit "absent" without a sighted, class-matched control needle through
the SAME instrument + path + artifact:

- `nq_absent <file> <query> <needle>` → `0 CERTIFIED-ABSENT | 1 PRESENT (+ the
  lines, never just a count) | 2 INSTRUMENT-BLIND | 3 NEEDLE-CLASS-MISMATCH`
- `nq_stream_contains <producer...> -- <query> <needle>` → `0 PRESENT |
  1 CERTIFIED-ABSENT | 2 INSTRUMENT-BLIND | 3 NEEDLE-CLASS-MISMATCH` — the
  consumer reads the producer to EOF, so the SIGPIPE/pipefail false-absent class
  (measured 400/400 at a 2 MB payload) is closed **by construction**, not by
  auditing call sites; and an absence verdict is returned ONLY after a
  class-matched needle is sighted through the SAME captured stream — the needle
  library certifies its own absences (§11.4.201(7)(b)).
- The instrument is injectable (`NQ_GREP`) so the blind-instrument path is
  itself testable — an unfalsifiable validator is unvalidated instrumentation.

### 3.2 `seams/status_custody/` — status custody at the database layer (SOL-01, §11.4.146(D3)+§11.4.115(F)+§11.4.34)

The seam travels WITH the data: SQLite triggers inside the tracker file bind
every writer, including raw `sqlite3` and writers that do not exist yet.

- `apply_custody.sh <db> [--init] [--no-probe]` — idempotent application +
  LIVE refusal probes (one per status-write path — UPDATE and INSERT) inside
  never-committed transactions (zero residue); success is reported only after
  BOTH refusals are OBSERVED on the target DB (§11.4.108 runtime signature).
- Triggers (8 = 3 UPDATE-path + 3 INSERT-path twins + 2 append-only guards):
  terminal status unwritable — via UPDATE **and** via INSERT (a row born
  terminal is the same custody event; the INSERT door was a proven-live PC-1
  bypass, RED transcript `test/evidence/INSERT_RED.txt`) — without registered
  guard + RED/GREEN verdict pair on DISTINCT artifact fingerprints; `Reopened`
  unwritable/un-insertable without staged By/Reason/Evidence attribution; every
  status change AND every item born in a custody state (terminal/Reopened)
  writes its OWN audit row (the DB is the historian); `item_history` is
  append-only (its INSERT stays legitimately open — appending IS the ledger's
  write operation).
- `custody_sweep.sh <db> [--require-triggers]` — build-seam full-table sweep
  for legacy/trigger-stripped DBs (4 finding classes, each mapped to a measured
  failure population; control-needled: an empty table is BLIND, never PASS).

### 3.3 `seams/evidence_class/` — evidence-class-at-closure (SOL-04, the discriminator)

`evidence_class_check.sh <defect-layer> <evidence-file>` — a closure's evidence
must be of the CLASS of the defect's layer, proven by MACHINE FIELDS
(`TARGET_FINGERPRINT`/`RUNTIME_OBSERVABLE`, `ARTIFACT_PATH`/`ARTIFACT_SHA256`,
`SOURCE_REF`), never by a label. The anti-echo rule refuses a grep transcript
wearing a runtime label (`WRONG-LAYER`) — a grep can never observe a pixel.
Source-on-source closes legitimately (no §11.4.201(1) false refusal).

## 4. Honest boundaries (§11.4.6 — what these seams do NOT catch)

**Covered write paths (exact):** `items.status` custody binds BOTH SQL write
paths — `UPDATE` (incl. `UPDATE ... SET status=...` of any row) and `INSERT`
(incl. the insert half of `INSERT OR REPLACE`) — for terminal statuses and
`Reopened`; `item_history` refuses `UPDATE` and `DELETE`. **Residual raw-SQL
paths NOT covered:** `DELETE FROM items` (erasing a terminal item + leaving its
history orphaned is not refused — §11.4.54 id-stability enforcement is OWED,
§5); direct `INSERT` into `guard_registry`/`verdicts`/`reopen_intake`
(fabricated chain rows — the first bullet below); `DROP TRIGGER` (second
bullet). The claim is bounded exactly here — nothing broader.

- **Fabricated evidence rows/fields.** Triggers verify chain SHAPE, the class
  checker verifies SHAPE + LAYER — not provenance/truth. Provenance is the
  §11.4.115(F) harness-written-verdict rule + the release-seam candidate-
  fingerprint join (SOL-02, OWED) + §1.1 mutation discipline. Layered, not
  duplicated.
- **`DROP TRIGGER`.** Possible for a determined writer; loud in `git diff` of a
  tracked DB, and caught by the sweep (`--require-triggers` + consequence
  checks C1–C4). Defense in depth, not a wall.
- **Oracle calibration.** Runtime-class evidence from a mis-calibrated analyzer
  still passes; §11.4.107(10) goldens remain necessary-not-sufficient.
- **The `Obsolete` path** has a different evidence shape — OWED.
- **Trigger throughput under ≥10 concurrent writers** — UNPROVEN; the §11.4.85
  stress suite is owed at integration.
- Measurements not routed through `needle.sh` stay exposed; adoption lint OWED.

## 5. OWED (next slices — proven POCs exist for all of these under the constitution's `docs/research/quality/solutions/poc/`)

1. **SOL-02** coverage-aware verdict semantics at the release-tag seam
   (`uncovered = registered ∧ topology-present ∧ no-verdict-for-candidate` blocks
   like a FAIL).
2. **Stop-seam completion gate** + **PostToolUse detective hooks** (ghost-edit
   checksum + exit-code) — the two unoccupied runtime seams.
3. **Go-native fuzzing corpus-replay** (committed crashers re-run in every
   `go test`) — the Go component of this repo.
4. Deterministic conformance checks (`go-arch-lint`-style, never similarity
   scoring); SOL-05 gate ledger; SOL-06 anchor-block integrity; SOL-07 intake
   dedup; SOL-08 scope coverage; SOL-09 detection-pressure scheduler; SOL-10
   misunderstanding-layer mechanics.
5. §11.4.85 stress/chaos suites; consumer pre-build gate code (`CM-*`) wiring
   these seams into `pre_build_verification.sh`-class suites; four-format doc
   exports.
6. **§11.4.197 OWED — §11.4.224 coverage floor (measured, not yet at floor).**
   Line-coverage lower bounds were MEASURED with the §11.4.224(E) PS4
   line-trace mechanism (`test/coverage_report.sh`; captured report
   `test/evidence/COVERAGE_20260723.txt`). Honest limits of the instrument:
   LINE coverage, NOT branch coverage; `set +x` regions and traps unaccounted;
   block terminators (`fi`/`done`/`}`/heredoc bodies) count in the denominator
   but never appear in a trace — so the figures are conservative LOWER BOUNDS
   that structurally undercount. OWED: per-corpus calibration of the 85%
   floor against these mechanics + raising any genuinely-under-floor file +
   a branch-capable instrument (e.g. `kcov`). No Go sources exist in this
   slice (`go test -cover` NOT APPLICABLE — honest §11.4.3 skip; Go enters
   with the OWED fuzz-corpus-replay slice).
7. **§11.4.197 OWED — row-DELETE custody.** `DELETE FROM items` on a terminal
   item is not refused by this slice (see §4); §11.4.54 id-stability
   enforcement at the DB layer is owed.

## 6. Tests + evidence

`test/run_all.sh` — 5 suites, golden-good + golden-bad + negative-control per
mechanism (§11.4.107(10)), authored and observed RED before the implementations
existed (§11.4.224; transcripts `test/evidence/RED_initial.txt` for the founding
slice, `test/evidence/INSERT_RED.txt` for the Phase-4-remediation INSERT-path +
stream-needle work, flipped GREEN in `test/evidence/GREEN_*.txt` +
`test/evidence/INSERT_GREEN.txt`). `test/test_out_of_box.sh` is the hermetic
out-of-box proof: it clones this repo's COMMITTED state into a throwaway
consumer project, runs the one-command install, and asserts a raw un-evidenced
terminal write is REFUSED — an uncommitted file cannot pass it.

## 7. License

MIT — see [LICENSE](LICENSE).
