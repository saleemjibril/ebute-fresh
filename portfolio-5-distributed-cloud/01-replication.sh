#!/bin/bash
# 01: a write on the primary reaches the replica, and the replica refuses writes.
#
#   ./setup-cluster.sh > setup-cluster.out 2>&1
#   ./01-replication.sh > 01-replication.out 2>&1

primary() { echo; echo "[primary 5440]"; psql -X -p 5440 -d ebute_fresh -e "$@"; }
replica() { echo; echo "[replica 5441]"; psql -X -p 5441 -d ebute_fresh -e "$@"; }

echo "--- A new intake is recorded at Kadawa. Intake officers write to the primary."
primary -c "
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received,
                         qty_remaining, farm_gate_price, received_at, received_by)
VALUES (2, 1, 1, 'A', 40, 40, 27000, '2026-11-12 07:05+01', 1)
RETURNING lot_id, qty_received, received_at;"

echo
echo "--- The sales desk reads stock from the replica straight after."
replica -c "
SELECT lot_id, commodity_name, grade, centre_name, qty_remaining, received_at
FROM lot_stock
WHERE lot_id = 19;"

echo
echo "--- How far behind the replica was, as the primary sees it."
primary -c "
SELECT application_name, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_not_yet_replayed,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;"

echo
echo "--- Someone points a write at the replica by mistake."
replica -c "
UPDATE produce_lot SET qty_remaining = 0 WHERE lot_id = 19;"
replica -c "
SELECT pg_is_in_recovery() AS read_only, current_setting('transaction_read_only') AS transaction_read_only;"

echo
echo "--- Both nodes hold the same data."
for port in 5440 5441; do
    psql -X -p $port -d ebute_fresh -A -t -c "
SELECT current_setting('cluster_name') || ': ' || count(*) || ' lots, '
       || sum(qty_remaining) || ' units in stock, '
       || (SELECT count(*) FROM payment) || ' payments'
FROM produce_lot;"
done
