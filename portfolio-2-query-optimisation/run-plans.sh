#!/bin/sh
# Runs EXPLAIN (ANALYZE, BUFFERS) on every query in queries.sql and saves
# the plans, with the list of indexes that existed at the time.
#
#   ./run-plans.sh plans-before.txt
#
# The queries are run once first and that output thrown away, so the saved
# timings are with the data already in memory and are comparable between runs.

set -e
out=${1:?usage: ./run-plans.sh output-file}
db=ebute_fresh
explain='EXPLAIN (ANALYZE, BUFFERS)'

psql -d "$db" -q -v explain="$explain" -f queries.sql > /dev/null

{
    echo "Plans captured $(date '+%Y-%m-%d %H:%M')"
    echo
    psql -d "$db" -c "SELECT tablename, indexname, indexdef FROM pg_indexes
                      WHERE schemaname = 'public'
                        AND tablename IN ('produce_lot', 'allocation', 'sales_order', 'order_line')
                      ORDER BY tablename, indexname;"
    psql -d "$db" -v explain="$explain" -f queries.sql
} > "$out" 2>&1

grep -E '^====|Execution Time' "$out"
