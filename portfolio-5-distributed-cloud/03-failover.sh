#!/bin/bash
# 03: the primary fails and the replica is promoted to take its place.
# Then the old primary is started again by mistake, to show why that is
# dangerous.
#
#   ./03-failover.sh > 03-failover.out 2>&1   (after 01 and 02)
#
# This leaves the cluster broken on purpose. Run setup-cluster.sh to rebuild it.

BASE=${BASE:-$HOME/ebute-cluster}
node() { local port=$1; shift; echo; echo "[port $port]"; psql -X -p "$port" -d ebute_fresh -e "$@"; }

echo "--- Last intake before the failure: Irish potato at Bukuru."
node 5440 -c "
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received,
                         qty_remaining, farm_gate_price, received_at, received_by)
VALUES (4, 2, 3, 'A', 60, 60, 37000, '2026-11-12 16:30+01', 2)
RETURNING lot_id;"
sleep 1
node 5440 -c "
SELECT application_name, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_not_yet_replayed
FROM pg_stat_replication;"

echo
echo "--- The primary crashes (stopped with -m immediate, like a power cut)."
pg_ctl -D "$BASE/primary" -m immediate stop
node 5440 -c "SELECT 1;"

echo
echo "--- The replica still answers reads, but nobody can record intakes or orders."
node 5441 -c "SELECT count(*) AS lots FROM produce_lot;"
node 5441 -c "
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received,
                         qty_remaining, farm_gate_price, received_at, received_by)
VALUES (13, 5, 5, 'A', 30, 30, 5600, '2026-11-12 16:50+01', 5);"

echo
echo "--- Promote the replica."
node 5441 -c "SELECT pg_promote();" \
          -c "SELECT current_setting('cluster_name') AS node, pg_is_in_recovery() AS read_only;" \
          -c "SELECT pg_walfile_name(pg_current_wal_lsn()) AS wal_file_now_on_timeline_2;"

echo
echo "--- Ijebu-Ode records an intake on the new primary."
node 5441 -c "
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received,
                         qty_remaining, farm_gate_price, received_at, received_by)
VALUES (13, 5, 5, 'A', 30, 30, 5600, '2026-11-12 16:50+01', 5)
RETURNING lot_id;"

echo
echo "--- Nothing committed before the crash was lost."
node 5441 -c "
SELECT lot_id, commodity_name, centre_name, qty_received, received_at
FROM lot_stock WHERE lot_id >= 19 ORDER BY lot_id;" \
          -c "SELECT count(*) AS payments, sum(amount) AS total FROM payment;"

echo
echo "--- Someone restarts the old primary without rebuilding it."
pg_ctl -D "$BASE/primary" -l "$BASE/primary.log" -w start
node 5440 -c "SELECT current_setting('cluster_name') AS node, pg_is_in_recovery() AS read_only;"
node 5440 -c "
INSERT INTO produce_lot (farmer_id, centre_id, commodity_id, grade, qty_received,
                         qty_remaining, farm_gate_price, received_at, received_by)
VALUES (3, 1, 1, 'B', 25, 25, 21000, '2026-11-12 17:10+01', 1)
RETURNING lot_id;"

echo
echo "--- Two primaries now accept writes, and they disagree."
for port in 5440 5441; do
    psql -X -p $port -d ebute_fresh -A -t -c "
SELECT current_setting('cluster_name') || ' (port $port): lots '
       || string_agg(lot_id || '=' || commodity_name, ', ' ORDER BY lot_id)
FROM lot_stock WHERE lot_id > 19;"
done

pg_ctl -D "$BASE/primary" -m fast stop
