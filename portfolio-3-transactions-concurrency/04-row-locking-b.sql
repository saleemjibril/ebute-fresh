-- 04 session B: Femi confirms order 9 half a second later. Lot 14 is locked
-- by A, so B has to wait. When A commits, B sees the real quantity left and
-- moves on to the next lot for the rest.

SELECT pg_sleep(0.5);

SELECT demo_note('B', 'BEGIN (read committed)');
BEGIN;

SELECT demo_note('B', 'calls confirm_order(9) ...');
SELECT confirm_order(9);
SELECT demo_note('B', 'confirm_order(9) done: took ' || quantity || ' crates from lot ' || lot_id)
FROM allocation WHERE order_id = 9 ORDER BY lot_id;

COMMIT;
SELECT demo_note('B', 'COMMIT');

-- Result
SELECT demo_note('B', 'RESULT lot ' || l.lot_id || ': received ' || l.qty_received
                      || ', allocated ' || coalesce(sum(a.quantity), 0)
                      || ', qty_remaining ' || l.qty_remaining)
FROM produce_lot l LEFT JOIN allocation a USING (lot_id)
WHERE l.lot_id IN (14, 19)
GROUP BY l.lot_id
ORDER BY l.lot_id;
