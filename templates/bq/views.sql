-- views.sql (harbor#1278) — the operator's own views of harbor's BigQuery logs (logging-design 4.7), per random id at day grain.
-- They stay in @DS@, which only the operator and the loader can read; nothing here is shared (shared-views.sql is). BigQuery SQL.
-- @DS@ is replaced by `project.dataset` at create time (gcp-setup.md, step 9). No view needs a login, and none could find one.

-- Silent laptops: the last day each id checked in, against the newest policy's silent_days.
CREATE OR REPLACE VIEW `@DS@.v_silent` AS
SELECT h.person_id, MAX(h.day) AS last_seen, DATE_DIFF(CURRENT_DATE(), MAX(h.day), DAY) AS days
FROM `@DS@.heartbeat` h
WHERE h.source = (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'source' AND value = 'member-hub')
GROUP BY h.person_id
HAVING days >= (SELECT silent_days FROM `@DS@.dim_policy` ORDER BY serial DESC LIMIT 1);

-- Block rate per rule and id: blocks over calls, the same day and source. Until a laptop sends activity it has no denominator.
CREATE OR REPLACE VIEW `@DS@.v_block_rate` AS
WITH blocks AS (
  SELECT d.source, d.person_id, d.day, d.rule, SUM(d.count) AS blocks
  FROM `@DS@.decision` d
  WHERE d.kind IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'hub_kind' AND value IN ('refusal', 'guard'))
    AND (d.verdict IS NULL OR d.verdict IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'verdict' AND value IN ('block', 'deny')))
  GROUP BY 1, 2, 3, 4),
calls AS (
  SELECT a.source, a.person_id, a.day, SUM(a.calls) AS calls FROM `@DS@.activity` a WHERE a.calls IS NOT NULL GROUP BY 1, 2, 3)
SELECT b.source, b.person_id, b.day, b.rule, b.blocks, c.calls, SAFE_DIVIDE(b.blocks, c.calls) AS rate
FROM blocks b LEFT JOIN calls c USING (source, person_id, day);

-- Version drift: each id's latest heartbeat against the newest policy's pin.
CREATE OR REPLACE VIEW `@DS@.v_drift` AS
WITH last AS (
  SELECT * FROM `@DS@.heartbeat` QUALIFY ROW_NUMBER() OVER (PARTITION BY person_id ORDER BY day DESC) = 1),
pol AS (SELECT * FROM `@DS@.dim_policy` ORDER BY serial DESC LIMIT 1)
SELECT l.person_id, l.day, l.core != p.pinned_core AS behind_core, l.contract != p.contract AS contract_mismatch,
       l.serial < p.serial AS serial_behind, l.mode
FROM last l CROSS JOIN pol p;

-- Approval latency: from the aggregate only, never per person (agg_approval has no id).
CREATE OR REPLACE VIEW `@DS@.v_approval_latency` AS
SELECT week, rule, tier, requests, approved, used, expired, SAFE_DIVIDE(expired, approved) AS expired_share,
       latency_p50_min, latency_p90_min, use_p50_min, people
FROM `@DS@.agg_approval`;

-- False-positive candidates per rule over 30 days: asks that proceeded, distinct ids, repeats of one shape. Candidates for a person
-- to read, never an automatic re-tier (encoding a fix is human-gated).
CREATE OR REPLACE VIEW `@DS@.v_fp` AS
SELECT d.rule,
       SUM(IF(d.outcome IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'outcome' AND value = 'proceeded'), d.count, 0)) AS proceeded,
       SUM(IF(d.kind IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'hub_kind' AND value = 'ask'), d.count, 0)) AS asks,
       COUNT(DISTINCT d.person_id) AS people, SUM(d.distinct_subjects) AS distinct_subjects, SUM(d.count) AS events,
       MAX(d.max_repeat) AS max_repeat,
       SUM(IF(d.verdict IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'verdict' AND value = 'shadow'), d.count, 0)) AS shadow_would_block
FROM `@DS@.decision` d
WHERE d.day >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY d.rule;

CREATE OR REPLACE VIEW `@DS@.v_check_failures` AS
SELECT c.day, c.check, SUM(c.count) AS failures, COUNT(DISTINCT c.person_id) AS people
FROM `@DS@.check_run` c
WHERE c.outcome IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'outcome' AND value = 'failed')
GROUP BY 1, 2;

CREATE OR REPLACE VIEW `@DS@.v_token_expiring` AS
SELECT l.person_id, MAX(l.day) AS day, MIN(l.days_left) AS days_left
FROM `@DS@.lifecycle` l
WHERE l.days_left IS NOT NULL
GROUP BY 1
HAVING MIN(l.days_left) <= 14;

-- The pipeline's own health: its absence is the alarm (J2, not scheduled).
CREATE OR REPLACE VIEW `@DS@.v_pipeline` AS
SELECT a.source, MAX(a.run_at) AS last_run, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(a.run_at), HOUR) AS hours_since,
       SUM(a.rows_refused) AS refused, SUM(a.laptop_dropped) AS laptop_dropped
FROM `@DS@.ingest_audit` a
GROUP BY 1;
