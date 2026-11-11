-- 04 session A: the same two orders as 03, but confirmed with
-- confirm_order(), which locks the lots it takes from (SELECT ... FOR UPDATE).
-- Chiamaka confirms order 8 and takes two seconds to print the delivery
-- note before committing.

SELECT demo_note('A', 'BEGIN (read committed)');
BEGIN;

SELECT confirm_order(8);
SELECT demo_note('A', 'confirm_order(8) done: took ' || quantity || ' crates from lot ' || lot_id || ', not committed yet')
FROM allocation WHERE order_id = 8;

SELECT pg_sleep(1);

SELECT demo_note('A', 'sees session ' || pid || ' waiting on ' || wait_event_type || '/' || wait_event
                      || ': ' || regexp_replace(query, '\s+', ' ', 'g'))
FROM pg_stat_activity
WHERE datname = current_database() AND wait_event_type = 'Lock';

SELECT pg_sleep(1);

COMMIT;
SELECT demo_note('A', 'COMMIT');
