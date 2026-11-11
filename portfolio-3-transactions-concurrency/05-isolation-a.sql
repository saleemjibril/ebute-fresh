-- 05 session A: Ngozi in finance runs the end-of-day stock report. It reads
-- the grade A tomato stock twice in one transaction (once for the summary,
-- once for the detail), two seconds apart. Run first at READ COMMITTED,
-- then at REPEATABLE READ.

SELECT demo_note('A', 'BEGIN ISOLATION LEVEL READ COMMITTED');
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT demo_note('A', 'first read: ' || sum(qty_remaining) || ' crates of grade A tomato')
FROM produce_lot WHERE commodity_id = 1 AND grade = 'A';
SELECT pg_sleep(2);
SELECT demo_note('A', 'second read: ' || sum(qty_remaining) || ' crates of grade A tomato')
FROM produce_lot WHERE commodity_id = 1 AND grade = 'A';
COMMIT;
SELECT demo_note('A', 'COMMIT. The two reads in one transaction disagree (non-repeatable read).');

SELECT pg_sleep(0.5);

SELECT demo_note('A', 'BEGIN ISOLATION LEVEL REPEATABLE READ');
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT demo_note('A', 'first read: ' || sum(qty_remaining) || ' crates of grade A tomato')
FROM produce_lot WHERE commodity_id = 1 AND grade = 'A';
SELECT pg_sleep(2);
SELECT demo_note('A', 'second read: ' || sum(qty_remaining) || ' crates of grade A tomato')
FROM produce_lot WHERE commodity_id = 1 AND grade = 'A';
COMMIT;
SELECT demo_note('A', 'COMMIT. Both reads saw the same snapshot.');

SELECT demo_note('A', 'new transaction, read again: ' || sum(qty_remaining) || ' crates of grade A tomato')
FROM produce_lot WHERE commodity_id = 1 AND grade = 'A';
