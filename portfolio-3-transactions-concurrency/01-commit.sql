-- 01: Commit
-- Confirm order 7 (Ofada Spot: 150 grade A yam, 4 bags grade A scotch
-- bonnet). The allocations, the lot quantities and the order status all
-- change together and become permanent at COMMIT.

\echo '--- Before: order 7 and the lots it can draw from'
SELECT order_id, status FROM sales_order WHERE order_id = 7;
SELECT lot_id, commodity_name, grade, qty_remaining, received_at::date
FROM lot_stock
WHERE (commodity_name, grade) IN (('Yam', 'A'), ('Scotch bonnet', 'A')) AND qty_remaining > 0
ORDER BY commodity_name, received_at;

BEGIN;
SELECT confirm_order(7);

\echo '--- Inside the transaction, before COMMIT'
SELECT * FROM allocation WHERE order_id = 7 ORDER BY line_no, lot_id;
COMMIT;

\echo '--- After COMMIT'
SELECT order_id, status FROM sales_order WHERE order_id = 7;
SELECT a.line_no, a.lot_id, a.quantity, l.qty_received, l.qty_remaining, l.received_at::date
FROM allocation a JOIN produce_lot l USING (lot_id)
WHERE a.order_id = 7
ORDER BY a.line_no;

\echo '--- Confirming the same order a second time is refused'
SELECT confirm_order(7);
