-- anti_bluff SOL-01 custody triggers (TEMPLATE — applied via apply_custody.sh).
-- THE LOAD-BEARING DESIGN CHOICE: these live IN THE DATABASE FILE, so they bind
-- EVERY writer — the sanctioned mutation tool AND the raw `sqlite3 "UPDATE ..."`
-- / `sqlite3 "INSERT ..."` bypasses that the forensic record proved (the INSERT
-- door: RED transcript test/evidence/INSERT_RED.txt). A seam implemented in a
-- wrapper tool can be gone around; a trigger travels with the data it protects
-- (through clones, copies, and CoW tracks). Both status-write paths — UPDATE
-- and INSERT — carry the same refusal logic (T1/T2/T3 + their T1i/T2i/T3i twins).
--
-- __AB_TERMINAL_LIST__ is substituted by apply_custody.sh from the consumer's
-- AB_TERMINAL_STATUSES (§11.4.35: vocabulary is consumer DATA; default
-- 'Fixed','Implemented','Completed'). Do NOT apply this file directly with
-- sqlite3 — use apply_custody.sh, which also makes the application idempotent
-- and proves the refusal live (§11.4.108 runtime signature).
--
-- The `Obsolete` path has a different evidence shape (obsolete-details) and is
-- OWED, not covered here — stated, never hidden (§11.4.6).

-- T1 — a terminal status is UNWRITABLE without the full custody chain:
--      registry row keyed by the EXACT item id
--      -> RED verdict with exit<>0
--      -> GREEN verdict with exit=0 on a DIFFERENT artifact fingerprint
--      (identical fingerprints prove the fix was never deployed, §11.4.115(F)).
CREATE TRIGGER custody_terminal_refuse
BEFORE UPDATE OF status ON items
WHEN NEW.status IN (__AB_TERMINAL_LIST__)
 AND NOT EXISTS (
   SELECT 1
   FROM guard_registry g
   JOIN verdicts red
     ON red.guard_id = g.guard_id AND red.polarity = 'RED' AND red.exit_code <> 0
   JOIN verdicts green
     ON green.guard_id = g.guard_id AND green.polarity = 'GREEN' AND green.exit_code = 0
    AND green.artifact_fingerprint <> red.artifact_fingerprint
   WHERE g.atm_id = NEW.atm_id
 )
BEGIN
  SELECT RAISE(ABORT,
    'CUSTODY-REFUSED: terminal status requires registered guard + RED/GREEN verdict pair on distinct artifact fingerprints (§11.4.146(D3) + §11.4.115(F))');
END;

-- T2 — 'Reopened' is UNWRITABLE without staged attribution (by/reason/evidence).
CREATE TRIGGER custody_reopen_refuse
BEFORE UPDATE OF status ON items
WHEN NEW.status = 'Reopened'
 AND NOT EXISTS (SELECT 1 FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0)
BEGIN
  SELECT RAISE(ABORT,
    'CUSTODY-REFUSED: Reopened requires a staged reopen_intake row (By/Reason/Evidence, §11.4.34)');
END;

-- T3 — every status change writes its own audit row. The DB is the historian;
--      no writer can "forget". Attribution comes from the staged intake row when
--      one exists (reopens), else from the GREEN verdict evidence (closures),
--      else the honest literal 'UNATTRIBUTED' (§11.4.6 — never invented).
CREATE TRIGGER custody_history_auto
AFTER UPDATE OF status ON items
WHEN OLD.status <> NEW.status
BEGIN
  INSERT INTO item_history(atm_id, event_type, by_actor, reason, evidence_path)
  VALUES(
    NEW.atm_id,
    NEW.status,
    COALESCE(
      (SELECT by_actor FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
      'UNATTRIBUTED'),
    (SELECT reason FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
    COALESCE(
      (SELECT evidence_path FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
      (SELECT v.evidence_path FROM guard_registry g JOIN verdicts v ON v.guard_id = g.guard_id
        WHERE g.atm_id = NEW.atm_id AND v.polarity = 'GREEN' AND v.exit_code = 0
        ORDER BY v.at DESC, v.verdict_id DESC LIMIT 1))
  );
  UPDATE reopen_intake SET consumed = 1 WHERE atm_id = NEW.atm_id AND consumed = 0;
END;

-- T1i — INSERT twin of T1 (IMPORTANT-1 remediation, 2026-07-23). A row BORN at a
--       terminal status is the same custody event as a row UPDATED into one: the
--       PC-1 raw-SQL bypass proved live through the INSERT door (a raw
--       `INSERT INTO items(...,status='Fixed')` was ACCEPTED with zero audit
--       rows on a fully-triggered DB — RED transcript test/evidence/INSERT_RED.txt).
--       Covers plain INSERT and the insert half of INSERT OR REPLACE.
CREATE TRIGGER custody_terminal_refuse_ins
BEFORE INSERT ON items
WHEN NEW.status IN (__AB_TERMINAL_LIST__)
 AND NOT EXISTS (
   SELECT 1
   FROM guard_registry g
   JOIN verdicts red
     ON red.guard_id = g.guard_id AND red.polarity = 'RED' AND red.exit_code <> 0
   JOIN verdicts green
     ON green.guard_id = g.guard_id AND green.polarity = 'GREEN' AND green.exit_code = 0
    AND green.artifact_fingerprint <> red.artifact_fingerprint
   WHERE g.atm_id = NEW.atm_id
 )
BEGIN
  SELECT RAISE(ABORT,
    'CUSTODY-REFUSED: terminal status requires registered guard + RED/GREEN verdict pair on distinct artifact fingerprints (§11.4.146(D3) + §11.4.115(F)) — INSERT path');
END;

-- T2i — INSERT twin of T2: a row born 'Reopened' needs the same staged
--       By/Reason/Evidence attribution as a flip to 'Reopened'.
CREATE TRIGGER custody_reopen_refuse_ins
BEFORE INSERT ON items
WHEN NEW.status = 'Reopened'
 AND NOT EXISTS (SELECT 1 FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0)
BEGIN
  SELECT RAISE(ABORT,
    'CUSTODY-REFUSED: Reopened requires a staged reopen_intake row (By/Reason/Evidence, §11.4.34) — INSERT path');
END;

-- T3i — INSERT twin of T3, scoped to the custody states (terminal + Reopened):
--       an item born in a custody state writes its own audit row, so the sweep's
--       C1/C2 invariants stay coherent for legitimate insert-at-terminal rows
--       (migrations/imports) and "born terminal with zero history" is impossible
--       by construction. Ordinary open-state inserts (Queued/In progress/...) are
--       item CREATION, not a status change — deliberately NOT audited here.
CREATE TRIGGER custody_history_auto_ins
AFTER INSERT ON items
WHEN NEW.status IN (__AB_TERMINAL_LIST__) OR NEW.status = 'Reopened'
BEGIN
  INSERT INTO item_history(atm_id, event_type, by_actor, reason, evidence_path)
  VALUES(
    NEW.atm_id,
    NEW.status,
    COALESCE(
      (SELECT by_actor FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
      'UNATTRIBUTED'),
    (SELECT reason FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
    COALESCE(
      (SELECT evidence_path FROM reopen_intake r WHERE r.atm_id = NEW.atm_id AND r.consumed = 0 ORDER BY r.at DESC, r.intake_id DESC LIMIT 1),
      (SELECT v.evidence_path FROM guard_registry g JOIN verdicts v ON v.guard_id = g.guard_id
        WHERE g.atm_id = NEW.atm_id AND v.polarity = 'GREEN' AND v.exit_code = 0
        ORDER BY v.at DESC, v.verdict_id DESC LIMIT 1))
  );
  UPDATE reopen_intake SET consumed = 1 WHERE atm_id = NEW.atm_id AND consumed = 0;
END;

-- T4/T5 — the audit ledger is append-only. History that can be edited is not
--         history (the impossible-sequence forensics depended on rows that
--         happened to survive; these make survival unconditional).
--         NO INSERT twin here BY DESIGN: appending IS the ledger's one legitimate
--         write operation (§11.4.201(1) — refusing it would be the false positive).
CREATE TRIGGER history_no_update
BEFORE UPDATE ON item_history
BEGIN SELECT RAISE(ABORT, 'CUSTODY-REFUSED: item_history is append-only'); END;

CREATE TRIGGER history_no_delete
BEFORE DELETE ON item_history
BEGIN SELECT RAISE(ABORT, 'CUSTODY-REFUSED: item_history is append-only'); END;
