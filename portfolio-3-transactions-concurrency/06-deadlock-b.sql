-- 06 session B: another order for the same two commodities, but typed the
-- other way round (plantain first). Starts half a second after A.

SELECT pg_sleep(0.5);
SELECT demo_note('B', 'round 1: BEGIN, wants plantain (lot 12) then tomato (lot 14)');
BEGIN;
SELECT 1 FROM produce_lot WHERE lot_id = 12 FOR UPDATE \g /dev/null
SELECT demo_note('B', 'locked lot 12 (plantain)');
SELECT pg_sleep(1);
SELECT demo_note('B', 'asks for lot 14 (tomato) ...');
SELECT 1 FROM produce_lot WHERE lot_id = 14 FOR UPDATE \g /dev/null
\if :ERROR
    ROLLBACK;
    SELECT demo_note('B', 'was rolled back by PostgreSQL to break the deadlock, so lot 12 is released');
\else
    SELECT demo_note('B', 'locked lot 14 (tomato)');
    COMMIT;
    SELECT demo_note('B', 'COMMIT');
\endif

SELECT pg_sleep(2.5);

SELECT demo_note('B', 'round 2: BEGIN, locks in commodity order: tomato (1) before plantain (5)');
BEGIN;
SELECT demo_note('B', 'asks for lot 14 (tomato) ...');
SELECT 1 FROM produce_lot WHERE lot_id = 14 FOR UPDATE \g /dev/null
SELECT demo_note('B', 'locked lot 14 (tomato)');
SELECT 1 FROM produce_lot WHERE lot_id = 12 FOR UPDATE \g /dev/null
SELECT demo_note('B', 'locked lot 12 (plantain)');
COMMIT;
SELECT demo_note('B', 'COMMIT. It waited, but nobody had to be rolled back.');
