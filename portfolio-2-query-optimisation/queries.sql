-- The six queries used for Portfolio 2. Each one is a key operation from
-- the case study.
--
-- Results:
--   psql -d ebute_fresh -f queries.sql > query-results.txt
-- Execution plans:
--   psql -d ebute_fresh -v explain='EXPLAIN (ANALYZE, BUFFERS)' -f queries.sql

\if :{?explain}
\else
  \set explain ''
\endif
\pset footer on


\echo
\echo ==== Q1. Grade A tomato in stock, oldest first (sales desk) ====
-- Run every time an order is taken, to see which lots to fill it from.
:explain
SELECT l.lot_id, cc.centre_name, l.qty_remaining, l.received_at,
       l.received_at::date + c.shelf_life_days AS best_before
FROM produce_lot l
JOIN commodity c          ON c.commodity_id = l.commodity_id
JOIN collection_centre cc ON cc.centre_id = l.centre_id
WHERE l.commodity_id = 1
  AND l.grade = 'A'
  AND l.qty_remaining > 0
ORDER BY l.received_at
LIMIT 10;


\echo
\echo ==== Q2. Unpaid lots for farmer 124 (finance, Friday payout run) ====
:explain
SELECT l.lot_id, c.commodity_name, l.grade, l.qty_received, l.farm_gate_price,
       l.qty_received * l.farm_gate_price AS amount_due, l.received_at
FROM produce_lot l
JOIN commodity c ON c.commodity_id = l.commodity_id
WHERE l.farmer_id = 124
  AND l.payout_id IS NULL
ORDER BY l.received_at;


\echo
\echo ==== Q3. Trace order 240965 back to the farmers who supplied it ====
:explain
SELECT ol.line_no, c.commodity_name, ol.grade, a.quantity,
       l.lot_id, l.received_at::date AS received,
       f.first_name || ' ' || f.last_name AS farmer, cc.centre_name
FROM order_line ol
JOIN commodity c          ON c.commodity_id = ol.commodity_id
JOIN allocation a         ON a.order_id = ol.order_id AND a.line_no = ol.line_no
JOIN produce_lot l        ON l.lot_id = a.lot_id
JOIN farmer f             ON f.farmer_id = l.farmer_id
JOIN collection_centre cc ON cc.centre_id = l.centre_id
WHERE ol.order_id = 240965
ORDER BY ol.line_no, l.lot_id;


\echo
\echo ==== Q4. Recall: who received tomatoes from farmer 1370, 1 to 15 October 2026 ====
-- The reverse of Q3. If a farmer's produce turns out to be contaminated,
-- every customer who got it has to be called.
:explain
SELECT cu.business_name, cu.phone, o.order_id, o.delivery_date,
       l.lot_id, a.quantity
FROM produce_lot l
JOIN allocation a   ON a.lot_id = l.lot_id
JOIN sales_order o  ON o.order_id = a.order_id
JOIN customer cu    ON cu.customer_id = o.customer_id
WHERE l.farmer_id = 1370
  AND l.commodity_id = 1
  AND l.received_at >= '2026-10-01'
  AND l.received_at <  '2026-10-16'
ORDER BY o.delivery_date, cu.business_name;


\echo
\echo ==== Q5. Sales and margin by month, commodity and source state, July to September 2026 ====
:explain
SELECT date_trunc('month', o.delivery_date)::date AS month,
       c.commodity_name,
       s.state_name,
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


\echo
\echo ==== Q6. Stock reaching best-before in the next two days, as at 10 November 2026 ====
-- The sales desk pushes these lots first, usually at a discount.
:explain
SELECT lot_id, commodity_name, grade, centre_name, qty_remaining,
       received_at::date AS received, best_before
FROM lot_stock
WHERE qty_remaining > 0
  AND best_before BETWEEN date '2026-11-10' AND date '2026-11-12'
ORDER BY best_before, lot_id;
