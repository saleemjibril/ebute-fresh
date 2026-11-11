-- 06 session A: an order for tomato and plantain.
-- Round 1 locks the lots in the order the lines were typed (tomato first).
-- Round 2 locks them in a fixed order (by commodity), as confirm_order does.

\echo '--- Round 1: lines locked in the order they were entered'
SELECT demo_note('A', 'round 1: BEGIN, wants tomato (lot 14) then plantain (lot 12)');
BEGIN;
SELECT 1 FROM produce_lot WHERE lot_id = 14 FOR UPDATE \g /dev/null
SELECT demo_note('A', 'locked lot 14 (tomato)');
SELECT pg_sleep(1);
SELECT demo_note('A', 'asks for lot 12 (plantain) ...');
SELECT 1 FROM produce_lot WHERE lot_id = 12 FOR UPDATE \g /dev/null
\if :ERROR
    ROLLBACK;
    SELECT demo_note('A', 'was rolled back by PostgreSQL to break the deadlock, so lot 14 is released');
\else
    SELECT demo_note('A', 'locked lot 12 (plantain)');
    COMMIT;
    SELECT demo_note('A', 'COMMIT');
\endif

SELECT pg_sleep(2);

\echo '--- Round 2: lots always locked in commodity order'
SELECT demo_note('A', 'round 2: BEGIN, locks in commodity order: tomato (1) before plantain (5)');
BEGIN;
SELECT 1 FROM produce_lot WHERE lot_id = 14 FOR UPDATE \g /dev/null
SELECT demo_note('A', 'locked lot 14 (tomato)');
SELECT pg_sleep(1);
SELECT 1 FROM produce_lot WHERE lot_id = 12 FOR UPDATE \g /dev/null
SELECT demo_note('A', 'locked lot 12 (plantain)');
COMMIT;
SELECT demo_note('A', 'COMMIT');
