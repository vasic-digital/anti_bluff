# anti_bluff — mechanical anti-bluff seams for any Helix-constitution project

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-07-23 |
| Status | active — first coherent slice (SOL-03 + SOL-01 + SOL-04); remaining mechanisms OWED (see §5) |
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
- `nq_stream_contains <producer...> -- <query>` — the consumer reads the
  producer to EOF, so the SIGPIPE/pipefail false-absent class (measured 400/400
  at a 2 MB payload) is closed **by construction**, not by auditing call sites.
- The instrument is injectable (`NQ_GREP`) so the blind-instrument path is
  itself testable — an unfalsifiable validator is unvalidated instrumentation.

### 3.2 `seams/status_custody/` — status custody at the database layer (SOL-01, §11.4.146(D3)+§11.4.115(F)+§11.4.34)

The seam travels WITH the data: SQLite triggers inside the tracker file bind
every writer, including raw `sqlite3` and writers that do not exist yet.

- `apply_custody.sh <db> [--init] [--no-probe]` — idempotent application +
  a LIVE refusal probe inside a never-committed transaction (zero residue);
  success is reported only after the refusal is OBSERVED on the target DB
  (§11.4.108 runtime signature).
- Triggers: terminal status unwritable without registered guard + RED/GREEN
  verdict pair on DISTINCT artifact fingerprints; `Reopened` unwritable without
  staged By/Reason/Evidence attribution; every status change writes its OWN
  audit row (the DB is the historian); `item_history` is append-only.
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

## 6. Tests + evidence

`test/run_all.sh` — 4 suites, golden-good + golden-bad + negative-control per
mechanism (§11.4.107(10)), authored and observed RED before the implementations
existed (§11.4.224; transcript `test/evidence/RED_initial.txt`), then GREEN
(`test/evidence/GREEN_*.txt`). `test/test_out_of_box.sh` is the hermetic
out-of-box proof: it clones this repo's COMMITTED state into a throwaway
consumer project, runs the one-command install, and asserts a raw un-evidenced
terminal write is REFUSED — an uncommitted file cannot pass it.

## 7. License

MIT — see [LICENSE](LICENSE).
