-- shared-views.sql (harbor#1278) — the only views anyone but the operator may read: anonymous totals, no person_id, and no group of
-- fewer than 5 people (#1278 "Log scope", level 2; legal/dpia.md R2). They live in the shared dataset @SHARED@ as authorized views
-- of @DS@, so a reader of them reads no table. Every view carries `people`, so tests/bq/views/shared.test.sh can see a small group.
-- Portable SQL on purpose (GROUP BY, HAVING, COUNT DISTINCT, CASE): the suite runs these same statements in sqlite.
-- @DS@ and @SHARED@ are replaced by `project.dataset` names at create time (gcp-setup.md, step 9).

CREATE OR REPLACE VIEW `@SHARED@.v_shared_rule_day` AS
SELECT d.day AS day, d.rule AS rule, d.kind AS kind, SUM(d.count) AS events, COUNT(DISTINCT d.person_id) AS people
FROM `@DS@.decision` d
GROUP BY d.day, d.rule, d.kind
HAVING COUNT(DISTINCT d.person_id) >= 5;

CREATE OR REPLACE VIEW `@SHARED@.v_shared_activity_day` AS
SELECT a.day AS day, a.tool AS tool, a.verdict AS verdict, SUM(a.calls) AS calls, COUNT(DISTINCT a.person_id) AS people
FROM `@DS@.activity` a
WHERE a.calls IS NOT NULL
GROUP BY a.day, a.tool, a.verdict
HAVING COUNT(DISTINCT a.person_id) >= 5;

-- the block rate: refusals and guard blocks per rule over all calls that day, each side from at least 5 people
CREATE OR REPLACE VIEW `@SHARED@.v_shared_block_rate` AS
SELECT b.day AS day, b.rule AS rule, b.blocks AS blocks, c.calls AS calls, b.people AS people
FROM (SELECT d.day AS day, d.rule AS rule, SUM(d.count) AS blocks, COUNT(DISTINCT d.person_id) AS people
      FROM `@DS@.decision` d
      WHERE d.kind IN (SELECT code FROM `@DS@.dim_enum` WHERE `set` = 'hub_kind' AND value IN ('refusal', 'guard'))
      GROUP BY d.day, d.rule
      HAVING COUNT(DISTINCT d.person_id) >= 5) b
JOIN (SELECT a.day AS day, SUM(a.calls) AS calls
      FROM `@DS@.activity` a
      WHERE a.calls IS NOT NULL
      GROUP BY a.day
      HAVING COUNT(DISTINCT a.person_id) >= 5) c
  ON c.day = b.day;

CREATE OR REPLACE VIEW `@SHARED@.v_shared_approval_week` AS
SELECT g.week AS week, g.rule AS rule, g.tier AS tier, g.requests AS requests, g.approved AS approved, g.expired AS expired,
       g.latency_p50_min AS latency_p50_min, g.latency_p90_min AS latency_p90_min, g.people AS people
FROM `@DS@.agg_approval` g
WHERE g.people >= 5;

CREATE OR REPLACE VIEW `@SHARED@.v_shared_sessions_day` AS
SELECT s.day AS day, SUM(s.started) AS started, SUM(s.ended) AS ended, COUNT(DISTINCT s.person_id) AS people
FROM `@DS@.session` s
GROUP BY s.day
HAVING COUNT(DISTINCT s.person_id) >= 5;
