-- Indexes added after the first round of plans (plans-before.txt).
--   psql -d ebute_fresh -f indexes.sql > indexes.out
-- To go back to the starting point, drop them again:
--   DROP INDEX produce_lot_in_stock_idx, produce_lot_farmer_idx,
--              allocation_lot_idx, sales_order_delivery_idx;

\timing on

-- Q1 and Q6. Only about 2,600 of 600,000 lots have stock left, and those
-- are the only ones the sales desk ever looks at, so the index only covers
-- them. received_at is last so Q1 gets its rows already in date order.
CREATE INDEX produce_lot_in_stock_idx
    ON produce_lot (commodity_id, grade, received_at)
    WHERE qty_remaining > 0;

-- Q2 and Q4. Foreign key with no index until now.
CREATE INDEX produce_lot_farmer_idx ON produce_lot (farmer_id);

-- Q4. allocation's primary key starts with order_id, which serves Q3 but
-- cannot be used to search by lot.
CREATE INDEX allocation_lot_idx ON allocation (lot_id);

-- Q5. Restricts the report to the quarter it asks for.
CREATE INDEX sales_order_delivery_idx ON sales_order (delivery_date);

ANALYZE produce_lot, allocation, sales_order;

\timing off

-- Index sizes, next to the primary keys of the same tables for comparison.
SELECT indexrelid::regclass AS index_name,
       indrelid::regclass   AS table_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index
WHERE indrelid::regclass::text IN ('produce_lot', 'allocation', 'sales_order')
ORDER BY indrelid::regclass::text, pg_relation_size(indexrelid) DESC;
