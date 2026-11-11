-- 03 session B: Femi fills order 9 (15 crates grade A tomato) the same
-- naive way, half a second after Chiamaka starts.

SELECT pg_sleep(0.5);

SELECT demo_note('B', 'BEGIN (read committed)');
BEGIN;

SELECT qty_remaining AS q FROM produce_lot WHERE lot_id = 14 \gset
SELECT demo_note('B', 'reads lot 14: ' || :q || ' crates left');

SELECT pg_sleep(1);

INSERT INTO allocation VALUES (9, 1, 14, 15);
UPDATE produce_lot SET qty_remaining = :q - 15 WHERE lot_id = 14;
UPDATE sales_order SET status = 'confirmed' WHERE order_id = 9;
SELECT demo_note('B', 'allocates 15 crates to order 9, sets lot 14 to ' || :q - 15);

COMMIT;
SELECT demo_note('B', 'COMMIT');

-- Result, once both have committed
SELECT pg_sleep(0.3);
SELECT demo_note('B', 'RESULT lot 14: received ' || qty_received
                      || ', allocated in total ' || (SELECT sum(quantity) FROM allocation WHERE lot_id = 14)
                      || ', qty_remaining says ' || qty_remaining)
FROM produce_lot WHERE lot_id = 14;
SELECT demo_note('B', 'RESULT 60 crates promised from a 50-crate lot. 10 crates oversold, and the CHECK constraint did not notice because 10 is a valid number.');
