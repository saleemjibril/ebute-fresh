-- 02: Rollback
-- Three ways a transaction's work gets undone.


\echo
\echo '=== 2a. Explicit ROLLBACK: the customer changes their mind mid-order ==='

BEGIN;
INSERT INTO sales_order (customer_id, taken_by, placed_at, delivery_date)
VALUES (4, 7, '2026-11-10 10:05+01', '2026-11-11');
INSERT INTO order_line
VALUES (currval(pg_get_serial_sequence('sales_order', 'order_id')), 1, 2, 'B', 15, 100000);

\echo '--- Inside the transaction the new order exists'
SELECT o.order_id, o.customer_id, l.commodity_id, l.grade, l.quantity
FROM sales_order o JOIN order_line l USING (order_id)
WHERE o.order_id = currval(pg_get_serial_sequence('sales_order', 'order_id'));

ROLLBACK;

\echo '--- After ROLLBACK it is gone, header and line both'
SELECT count(*) AS orders_for_customer_4_on_10_nov
FROM sales_order
WHERE customer_id = 4 AND placed_at::date = '2026-11-10';


\echo
\echo '=== 2b. An error aborts the whole transaction ==='
-- GreenBasket asks for 100 crates of grade A tomato. Only 65 are in stock
-- (25 in lot 14, 40 in lot 19). confirm_order takes all 65 before it finds
-- the shortfall and raises an error. None of it may stick.

BEGIN;
INSERT INTO sales_order (customer_id, taken_by, placed_at, delivery_date)
VALUES (2, 6, '2026-11-10 10:20+01', '2026-11-11');
INSERT INTO order_line
VALUES (currval(pg_get_serial_sequence('sales_order', 'order_id')), 1, 1, 'A', 100, 42000);

SELECT confirm_order(currval(pg_get_serial_sequence('sales_order', 'order_id')));

\echo '--- Any further statement is refused until the transaction ends'
SELECT count(*) FROM allocation;

ROLLBACK;

\echo '--- After ROLLBACK: no new order, no allocations, tomato stock untouched'
SELECT count(*) AS orders_placed_10_nov_10_20
FROM sales_order WHERE placed_at = '2026-11-10 10:20+01';
SELECT count(*) AS allocations_in_table FROM allocation;   -- 14, as in the sample data
SELECT lot_id, qty_remaining FROM produce_lot WHERE lot_id IN (14, 19) ORDER BY lot_id;


\echo
\echo '=== 2c. Savepoints: one failure in the Friday payout run ==='
-- Finance pays three farmers in one transaction. Each farmer gets a
-- savepoint, so a mistake with one farmer only undoes that farmer.
-- The bank reference for Adewale Ogunleye (farmer 10) is mistyped as one
-- that was already used last week.

\echo '--- Unpaid lots before the run'
SELECT farmer_id, lot_id, qty_received * farm_gate_price AS value
FROM produce_lot
WHERE farmer_id IN (2, 10, 12) AND payout_id IS NULL
ORDER BY farmer_id, lot_id;

BEGIN;

SAVEPOINT farmer_12;
WITH p AS (
    INSERT INTO farmer_payout (farmer_id, amount, paid_at, bank_ref, paid_by)
    SELECT 12, sum(qty_received * farm_gate_price), '2026-11-13 14:02+01', 'FT26111300201', 8
    FROM produce_lot WHERE farmer_id = 12 AND payout_id IS NULL
    RETURNING payout_id
)
UPDATE produce_lot SET payout_id = (SELECT payout_id FROM p)
WHERE farmer_id = 12 AND payout_id IS NULL;
RELEASE SAVEPOINT farmer_12;

SAVEPOINT farmer_10;
WITH p AS (
    INSERT INTO farmer_payout (farmer_id, amount, paid_at, bank_ref, paid_by)
    SELECT 10, sum(qty_received * farm_gate_price), '2026-11-13 14:04+01', 'FT26110600118', 8
    FROM produce_lot WHERE farmer_id = 10 AND payout_id IS NULL
    RETURNING payout_id
)
UPDATE produce_lot SET payout_id = (SELECT payout_id FROM p)
WHERE farmer_id = 10 AND payout_id IS NULL;
ROLLBACK TO SAVEPOINT farmer_10;

SAVEPOINT farmer_2;
WITH p AS (
    INSERT INTO farmer_payout (farmer_id, amount, paid_at, bank_ref, paid_by)
    SELECT 2, sum(qty_received * farm_gate_price), '2026-11-13 14:06+01', 'FT26111300203', 8
    FROM produce_lot WHERE farmer_id = 2 AND payout_id IS NULL
    RETURNING payout_id
)
UPDATE produce_lot SET payout_id = (SELECT payout_id FROM p)
WHERE farmer_id = 2 AND payout_id IS NULL;
RELEASE SAVEPOINT farmer_2;

COMMIT;

\echo '--- After COMMIT: farmers 12 and 2 are paid, farmer 10 is still waiting'
SELECT l.farmer_id, l.lot_id, l.payout_id, p.amount, p.bank_ref
FROM produce_lot l
LEFT JOIN farmer_payout p USING (payout_id)
WHERE l.farmer_id IN (2, 10, 12) AND l.received_at >= '2026-11-05'
ORDER BY l.farmer_id, l.lot_id;
