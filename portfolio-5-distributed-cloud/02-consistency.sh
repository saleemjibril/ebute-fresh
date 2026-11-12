#!/bin/bash
# 02: consistency between primary and replica.
#   A. Asynchronous (the default): a replica that falls behind gives stale reads.
#   B. Synchronous with remote_apply: the commit waits until the replica has it.
#   C. The cost of B: if the replica is down, commits on the primary wait too.
#
# To make the replica "fall behind" on demand, replay is paused with
# pg_wal_replay_pause(). It still receives WAL, it just does not apply it,
# which is what a slow or overloaded replica looks like from outside.
#
#   ./02-consistency.sh > 02-consistency.out 2>&1   (after setup-cluster.sh and 01)

BASE=${BASE:-$HOME/ebute-cluster}
primary() { echo; echo "[primary 5440]"; psql -X -p 5440 -d ebute_fresh -e "$@"; }
replica() { echo; echo "[replica 5441]"; psql -X -p 5441 -d ebute_fresh -e "$@"; }
check_order_6() { replica -c "SELECT payment_id, amount, reference FROM payment WHERE order_id = 6;"; }

echo "=== A. Asynchronous replication: stale read"
echo
echo "--- The replica falls behind."
replica -c "SELECT pg_wal_replay_pause();" -c "SELECT pg_get_wal_replay_pause_state();"

echo
echo "--- Lagoon View pays part of order 6. Finance records it on the primary."
primary -c "
INSERT INTO payment (order_id, amount, method, reference, paid_at)
VALUES (6, 600000, 'transfer', 'NIP000231112058', '2026-11-12 10:14+01')
RETURNING payment_id;"

echo
echo "--- The customer calls the sales desk, whose screen reads from the replica."
check_order_6
primary -c "
SELECT sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_not_yet_replayed
FROM pg_stat_replication;"

echo
echo "--- The replica catches up."
replica -c "SELECT pg_wal_replay_resume();"
sleep 1
check_order_6

echo
echo "=== B. Synchronous replication with remote_apply"
primary -c "ALTER SYSTEM SET synchronous_standby_names = 'ebute_replica';" \
        -c "ALTER SYSTEM SET synchronous_commit = 'remote_apply';" \
        -c "SELECT pg_reload_conf();"
sleep 1
primary -c "SELECT application_name, sync_state FROM pg_stat_replication;"

echo
echo "--- The replica falls behind again."
replica -c "SELECT pg_wal_replay_pause();"

echo
echo "--- Finance records the balance of order 6. This session runs in the background."
out=$(mktemp)
psql -X -p 5440 -d ebute_fresh -e > "$out" 2>&1 <<'EOF' &
\timing on
INSERT INTO payment (order_id, amount, method, reference, paid_at)
VALUES (6, 630000, 'transfer', 'NIP000231112311', '2026-11-12 15:40+01');
EOF
sleep 1
echo
echo "--- One second later, what is that session doing?"
primary -c "
SELECT pid, wait_event_type, wait_event, state, left(query, 40) AS query
FROM pg_stat_activity
WHERE wait_event = 'SyncRep';"
sleep 2
echo
echo "--- Three seconds in, the replica resumes replay."
replica -c "SELECT pg_wal_replay_resume();"
wait
echo
echo "--- Output of the background session:"
sed 's/^/   /' "$out"
echo
echo "--- The moment the commit returned, the replica already had it."
check_order_6

echo
echo "=== C. Synchronous replication when the replica is down"
pg_ctl -D "$BASE/replica" -m fast stop
primary -c "SELECT count(*) AS replicas_connected FROM pg_stat_replication;"

echo
echo "--- Finance records a payment for order 7. This session runs in the background."
psql -X -p 5440 -d ebute_fresh -e > "$out" 2>&1 <<'EOF2' &
\timing on
INSERT INTO payment (order_id, amount, method, reference, paid_at)
VALUES (7, 855000, 'transfer', 'NIP000231112402', '2026-11-12 16:05+01');
EOF2
sleep 5
echo
echo "--- Five seconds later it is still waiting for a replica that is not there."
primary -c "
SELECT pid, wait_event, now() - query_start AS waiting_for, left(query, 40) AS query
FROM pg_stat_activity
WHERE wait_event = 'SyncRep';"
# statement_timeout does not help here: the wait happens after the statement,
# during commit. I tried it first and the INSERT waited over a minute.
echo
echo "--- Finance gives up and the session is cancelled."
primary -c "
SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE wait_event = 'SyncRep';"
wait
echo
echo "--- Output of the background session:"
sed 's/^/   /' "$out"
primary -c "SELECT payment_id, order_id, amount FROM payment WHERE order_id = 7;"

echo
echo "--- The replica comes back and catches up from the replication slot."
pg_ctl -D "$BASE/replica" -l "$BASE/replica.log" -w start
sleep 1
replica -c "SELECT payment_id, order_id, amount FROM payment WHERE order_id = 7;"

echo
echo "--- Back to asynchronous replication for the rest of the portfolio."
primary -c "ALTER SYSTEM RESET synchronous_standby_names;" \
        -c "ALTER SYSTEM RESET synchronous_commit;" \
        -c "SELECT pg_reload_conf();"
sleep 1
primary -c "SELECT application_name, sync_state FROM pg_stat_replication;"
rm -f "$out"
