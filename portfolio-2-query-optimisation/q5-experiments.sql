-- Q5 did not get faster with indexes. Two experiments to find out why and
-- what does help. Run after indexes.sql:
--   psql -d ebute_fresh -f q5-experiments.sql > q5-experiments.out 2>&1

-- Warm-up, so both tests below start with the data in memory.
SELECT count(*) FROM allocation;
SELECT count(*) FROM produce_lot;


\echo
\echo ==== Test 1: force the planner to use indexes instead of hash joins ====
-- If the planner is right to prefer hash joins and sequential scans here,
-- taking those options away should make the query slower, not faster.

BEGIN;
SET LOCAL enable_hashjoin = off;
SET LOCAL enable_mergejoin = off;
SET LOCAL enable_seqscan = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', o.delivery_date)::date AS month,
       c.commodity_name, s.state_name,
       sum(a.quantity) AS units,
       sum(a.quantity * ol.unit_price) AS revenue,
       sum(a.quantity * (ol.unit_price - l.farm_gate_price)) AS margin
FROM sales_order o
JOIN order_line ol        ON ol.order_id = o.order_id
JOIN allocation a         ON a.order_id = ol.order_id AND a.line_no = ol.line_no
JOIN produce_lot l        ON l.lot_id = a.lot_id
JOIN collection_centre cc ON cc.centre_id = l.centre_id
JOIN state s              ON s.state_code = cc.state_code
JOIN commodity c          ON c.commodity_id = ol.commodity_id
WHERE o.status = 'delivered'
  AND o.delivery_date >= '2026-07-01'
  AND o.delivery_date <  '2026-10-01'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
ROLLBACK;


\echo
\echo ==== Test 2: monthly summary kept in a materialised view ====
-- Delivered orders do not change once the month is over, so the totals can
-- be worked out once and stored. The view is refreshed overnight; the
-- report then reads 36 rows instead of joining 125,000.

DROP MATERIALIZED VIEW IF EXISTS monthly_sales;

\timing on
CREATE MATERIALIZED VIEW monthly_sales AS
SELECT date_trunc('month', o.delivery_date)::date AS month,
       ol.commodity_id,
       cc.state_code,
       sum(a.quantity) AS units,
       sum(a.quantity * ol.unit_price) AS revenue,
       sum(a.quantity * (ol.unit_price - l.farm_gate_price)) AS margin
FROM sales_order o
JOIN order_line ol        ON ol.order_id = o.order_id
JOIN allocation a         ON a.order_id = ol.order_id AND a.line_no = ol.line_no
JOIN produce_lot l        ON l.lot_id = a.lot_id
JOIN collection_centre cc ON cc.centre_id = l.centre_id
WHERE o.status = 'delivered'
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX ON monthly_sales (month, commodity_id, state_code);

-- What the overnight job costs. CONCURRENTLY lets reports keep reading the
-- old figures while it runs; it needs the unique index above.
REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_sales;
\timing off

ANALYZE monthly_sales;

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.month, c.commodity_name, s.state_name, m.units, m.revenue, m.margin
FROM monthly_sales m
JOIN commodity c ON c.commodity_id = m.commodity_id
JOIN state s     ON s.state_code = m.state_code
WHERE m.month >= '2026-07-01' AND m.month < '2026-10-01'
ORDER BY 1, 2, 3;

\echo
\echo Same figures as the original Q5? Rows that differ (expect none):
(SELECT m.month, c.commodity_name, s.state_name, m.units, m.revenue, m.margin
 FROM monthly_sales m
 JOIN commodity c ON c.commodity_id = m.commodity_id
 JOIN state s     ON s.state_code = m.state_code
 WHERE m.month >= '2026-07-01' AND m.month < '2026-10-01')
EXCEPT
(SELECT date_trunc('month', o.delivery_date)::date, c.commodity_name, s.state_name,
        sum(a.quantity), sum(a.quantity * ol.unit_price),
        sum(a.quantity * (ol.unit_price - l.farm_gate_price))
 FROM sales_order o
 JOIN order_line ol        ON ol.order_id = o.order_id
 JOIN allocation a         ON a.order_id = ol.order_id AND a.line_no = ol.line_no
 JOIN produce_lot l        ON l.lot_id = a.lot_id
 JOIN collection_centre cc ON cc.centre_id = l.centre_id
 JOIN state s              ON s.state_code = cc.state_code
 JOIN commodity c          ON c.commodity_id = ol.commodity_id
 WHERE o.status = 'delivered'
   AND o.delivery_date >= '2026-07-01' AND o.delivery_date < '2026-10-01'
 GROUP BY 1, 2, 3);
