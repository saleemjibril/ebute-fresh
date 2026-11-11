-- 05 session B: the sales desk confirms one order during each of A's two
-- report transactions. Each confirm_order call is its own transaction and
-- commits straight away.

SELECT pg_sleep(1);
SELECT confirm_order(8);
SELECT demo_note('B', 'confirm_order(8) committed: 20 crates of grade A tomato taken');

SELECT pg_sleep(2.5);
SELECT confirm_order(9);
SELECT demo_note('B', 'confirm_order(9) committed: 15 crates of grade A tomato taken');
