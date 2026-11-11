-- 03 session A: Chiamaka fills order 8 (20 crates grade A tomato) the naive
-- way: read how much is left, work out the new figure in the application,
-- write it back. No locking.

SELECT demo_note('A', 'BEGIN (read committed)');
BEGIN;

SELECT qty_remaining AS q FROM produce_lot WHERE lot_id = 14 \gset
SELECT demo_note('A', 'reads lot 14: ' || :q || ' crates left');

SELECT pg_sleep(1);

INSERT INTO allocation VALUES (8, 1, 14, 20);
UPDATE produce_lot SET qty_remaining = :q - 20 WHERE lot_id = 14;
UPDATE sales_order SET status = 'confirmed' WHERE order_id = 8;
SELECT demo_note('A', 'allocates 20 crates to order 8, sets lot 14 to ' || :q - 20);

COMMIT;
SELECT demo_note('A', 'COMMIT');
