-- Constraint tests. Run after schema.sql and sample-data.sql:
--   psql -d ebute_fresh -e -f constraint-tests.sql > constraint-tests.out 2>&1
--
-- Part 1: every statement here should FAIL. Each runs on its own, so one
-- failure does not stop the rest.
-- Part 2: checks on the sample data. Every query should return 0 rows.

\echo
\echo ===== Part 1: inserts and updates that must be rejected =====

\echo
\echo -- 1. Grade D does not exist
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received, qty_remaining,
                         farm_gate_price, received_by)
VALUES (1, 1, 1, 'D', 10, 10, 24000, 1);

\echo
\echo -- 2. Cannot have more left than was received
UPDATE produce_lot SET qty_remaining = qty_received + 5 WHERE lot_id = 2;

\echo
\echo -- 3. Stock cannot go negative (overselling)
UPDATE produce_lot SET qty_remaining = qty_remaining - 31 WHERE lot_id = 2;

\echo
\echo -- 4. Officer from Bukuru recording a lot at Kadawa
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received, qty_remaining,
                         farm_gate_price, received_by)
VALUES (1, 1, 1, 'A', 10, 10, 24000, 2);

\echo
\echo -- 5. Sales staff cannot record an intake
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received, qty_remaining,
                         farm_gate_price, received_by)
VALUES (1, 1, 1, 'A', 10, 10, 24000, 6);

\echo
\echo -- 6. Lot 14 (Aminu Garba) paid through payout 1, which belongs to Musa Abdullahi
UPDATE produce_lot SET payout_id = 1 WHERE lot_id = 14;

\echo
\echo -- 7. Intake officer with no centre
INSERT INTO staff (full_name, role, centre_id, phone)
VALUES ('Test Officer', 'intake_officer', NULL, '+2348030000001');

\echo
\echo -- 8. Phone number in local format instead of +234
INSERT INTO farmer (first_name, last_name, phone, home_centre_id)
VALUES ('Sani', 'Bello', '08031234567', 1);

\echo
\echo -- 9. Two farmers with the same phone number
INSERT INTO farmer (first_name, last_name, phone, home_centre_id)
VALUES ('Sani', 'Bello', '+2348036621904', 1);

\echo
\echo -- 10. Bank name without an account number
INSERT INTO farmer (first_name, last_name, phone, home_centre_id, bank_name)
VALUES ('Sani', 'Bello', '+2348030000002', 1, 'UBA');

\echo
\echo -- 11. Order for a customer that does not exist
INSERT INTO sales_order (customer_id, taken_by, delivery_date) VALUES (99, 6, '2026-11-12');

\echo
\echo -- 12. Unknown order status
UPDATE sales_order SET status = 'shipped' WHERE order_id = 6;

\echo
\echo -- 13. Same commodity and grade twice on one order
INSERT INTO order_line VALUES (6, 4, 1, 'A', 5, 42000);

\echo
\echo -- 14. Zero quantity on an order line
INSERT INTO order_line VALUES (7, 3, 2, 'A', 0, 120000);

\echo
\echo -- 15. Allocating a yam lot (8) to a tomato line (order 6 line 1)
INSERT INTO allocation VALUES (6, 1, 8, 5);

\echo
\echo -- 16. Allocating to an order line that does not exist
INSERT INTO allocation VALUES (7, 9, 15, 10);

\echo
\echo -- 17. Transfer with no reference
INSERT INTO payment (order_id, amount, method) VALUES (4, 500000, 'transfer');

\echo
\echo -- 18. Same bank reference used twice
INSERT INTO payment (order_id, amount, method, reference)
VALUES (6, 100000, 'transfer', 'NIP000231104771');

\echo
\echo -- 19. Deleting a farmer who has lots
DELETE FROM farmer WHERE farmer_id = 1;


\echo
\echo ===== Part 2: consistency checks on the sample data (expect 0 rows each) =====

\echo
\echo -- 20. qty_remaining agrees with what has been allocated
SELECT l.lot_id, l.qty_received, l.qty_remaining,
       coalesce(sum(a.quantity), 0) AS allocated
FROM produce_lot l
LEFT JOIN allocation a ON a.lot_id = l.lot_id
GROUP BY l.lot_id
HAVING l.qty_remaining <> l.qty_received - coalesce(sum(a.quantity), 0);

\echo
\echo -- 21. Confirmed and delivered lines are fully allocated
SELECT ol.order_id, ol.line_no, ol.quantity, coalesce(sum(a.quantity), 0) AS allocated
FROM order_line ol
JOIN sales_order o ON o.order_id = ol.order_id
LEFT JOIN allocation a ON (a.order_id, a.line_no) = (ol.order_id, ol.line_no)
WHERE o.status IN ('confirmed', 'delivered')
GROUP BY ol.order_id, ol.line_no, ol.quantity
HAVING coalesce(sum(a.quantity), 0) <> ol.quantity;

\echo
\echo -- 22. Pending and cancelled orders hold no stock
SELECT a.*
FROM allocation a
JOIN sales_order o ON o.order_id = a.order_id
WHERE o.status IN ('pending', 'cancelled');

\echo
\echo -- 23. Each payout equals the value of the lots it settles
SELECT p.payout_id, p.amount, sum(l.qty_received * l.farm_gate_price) AS lots_value
FROM farmer_payout p
JOIN produce_lot l ON l.payout_id = p.payout_id
GROUP BY p.payout_id, p.amount
HAVING p.amount <> sum(l.qty_received * l.farm_gate_price);

\echo
\echo -- 24. No order has been paid more than its value
SELECT o.order_id, t.order_value, sum(p.amount) AS paid
FROM sales_order o
JOIN (SELECT order_id, sum(quantity * unit_price) AS order_value
      FROM order_line GROUP BY order_id) t ON t.order_id = o.order_id
JOIN payment p ON p.order_id = o.order_id
GROUP BY o.order_id, t.order_value
HAVING sum(p.amount) > t.order_value;

\echo
\echo -- 25. Nothing was allocated from a lot before it was received
SELECT a.order_id, a.line_no, a.lot_id, l.received_at, o.delivery_date
FROM allocation a
JOIN produce_lot l ON l.lot_id = a.lot_id
JOIN sales_order o ON o.order_id = a.order_id
WHERE l.received_at::date > o.delivery_date;


\echo
\echo ===== Summary: outstanding balances =====
SELECT o.order_id, c.business_name, o.status,
       t.order_value, coalesce(sum(p.amount), 0) AS paid,
       t.order_value - coalesce(sum(p.amount), 0) AS balance
FROM sales_order o
JOIN customer c ON c.customer_id = o.customer_id
JOIN (SELECT order_id, sum(quantity * unit_price) AS order_value
      FROM order_line GROUP BY order_id) t ON t.order_id = o.order_id
LEFT JOIN payment p ON p.order_id = o.order_id
WHERE o.status <> 'cancelled'
GROUP BY o.order_id, c.business_name, o.status, t.order_value
ORDER BY o.order_id;
