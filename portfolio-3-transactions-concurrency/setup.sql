-- Resets the database to a known state before each demo.
-- run-all.sh calls this before every script, so each output starts from
-- the same data.
--
-- It rebuilds the Portfolio 1 schema and sample week, so it also removes
-- the generated data from Portfolio 2.

\set QUIET on
SET client_min_messages = warning;

\ir ../portfolio-1-database-design/schema.sql
\ir ../portfolio-1-database-design/sample-data.sql
\ir confirm-order.sql

-- Tuesday 10 November, morning. A new lot of grade A tomato has come in at
-- Kadawa, and the sales desk has taken two orders that both need it.
BEGIN;

INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received, qty_remaining,
                         farm_gate_price, received_at, received_by)
VALUES (2, 1, 1, 'A', 40, 40, 27000, '2026-11-10 07:20+01', 1);           -- lot 19

INSERT INTO sales_order (customer_id, taken_by, placed_at, delivery_date) VALUES
    (2, 6, '2026-11-10 09:10+01', '2026-11-11'),                            -- order 8
    (3, 7, '2026-11-10 09:12+01', '2026-11-12');                            -- order 9

INSERT INTO order_line VALUES
    (8, 1, 1, 'A', 20, 42000),
    (9, 1, 1, 'A', 15, 42000);

COMMIT;

-- Used by the two-session demos to print a timestamped line, so the output
-- of both sessions can be merged into one timeline.
CREATE OR REPLACE FUNCTION demo_note(who text, msg text) RETURNS text
LANGUAGE sql AS $$
    SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') || '|' || who || '|' || msg
$$;

\set QUIET off
