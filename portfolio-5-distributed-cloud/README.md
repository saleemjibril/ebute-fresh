# Portfolio 5: Distributed and Cloud Database

Everything at Ebute Fresh runs through one database. Intake officers at five centres
record deliveries in it, the sales desk reserves stock from it, and finance pays
farmers out of it. If that one server goes down, intake stops in five states at once.
This portfolio sets up a primary and a streaming replica of the Ebute Fresh database,
and uses them to look at replication, consistency, failover and availability. Sharding
and cloud deployment are discussed at the end.

## Files

| File | What it shows |
|---|---|
| `setup-cluster.sh` / `.out` | Builds a primary and a streaming replica and loads the Portfolio 1 data |
| `01-replication.sh` / `.out` | A write on the primary appears on the replica; the replica refuses writes |
| `02-consistency.sh` / `.out` | Stale reads with asynchronous replication, and what synchronous replication costs |
| `03-failover.sh` / `.out` | The primary crashes, the replica is promoted, and the old primary comes back by mistake |

## The set-up

Both nodes run on my laptop as separate PostgreSQL 16 servers, each with its own data
directory under `~/ebute-cluster`. The server on port 5432 from the other portfolios
is not touched.

| Node | Port | Role |
|---|---|---|
| `ebute_primary` | 5440 | Takes every write: intakes, orders, payments, payouts |
| `ebute_replica` | 5441 | Read-only copy, kept up to date by streaming the primary's WAL |

`setup-cluster.sh` does the following:

1. Creates the primary with `initdb` and loads the Portfolio 1 schema and sample week.
2. Creates a `replicator` role with the REPLICATION attribute.
3. Clones the primary with `pg_basebackup -R -C -S ebute_replica_slot`. `-R` writes
   `standby.signal` and the connection details, so the copy starts as a standby. `-C -S`
   creates a replication slot on the primary. With the slot, the primary keeps any WAL
   the replica has not received yet, so a replica that was switched off can catch up
   afterwards. Part C of 02 relies on this.
4. Starts the replica on port 5441 and checks `pg_stat_replication` on the primary and
   `pg_stat_wal_receiver` on the replica. Both show `streaming`.

## How to run

```
cd portfolio-5-distributed-cloud
./setup-cluster.sh > setup-cluster.out 2>&1
./01-replication.sh > 01-replication.out 2>&1
./02-consistency.sh > 02-consistency.out 2>&1
./03-failover.sh    > 03-failover.out 2>&1
```

They must run in this order, because each one continues from the state the one before
left behind. 03 leaves the cluster broken on purpose, and `setup-cluster.sh` rebuilds it.
To remove everything afterwards:

```
pg_ctl -D ~/ebute-cluster/replica stop; pg_ctl -D ~/ebute-cluster/primary stop
rm -rf ~/ebute-cluster
```

## 01 Replication

A new tomato lot is recorded at Kadawa on the primary. A query on the replica straight
afterwards returns it. `pg_stat_replication` showed the replica 0 bytes behind, with a
replay lag of 1.3 ms.

An UPDATE sent to the replica fails with `cannot execute UPDATE in a read-only
transaction`. A replica can only take reads, so intakes, orders and payments must always
go to the primary. Both nodes end with 19 lots, 1,244 units in stock and 5 payments.

## 02 Consistency

The replica in 01 was 1.3 ms behind, which hides the problem. To make the replica fall
behind on demand, I paused replay on it with `pg_wal_replay_pause()`. It still
receives WAL from the primary but does not apply it. From outside, that looks the same
as a slow or overloaded replica.

**A. Asynchronous (the default): stale reads.** Lagoon View pays ₦600,000 towards order
6, and finance records it on the primary. The sales desk checks on a screen that reads
from the replica, and sees no payment at all. The primary showed the replica 1,768 bytes
behind. Once replay resumed, the payment appeared. The replica is eventually consistent:
it will get there, but a read can come back out of date with no warning.

**B. Synchronous with `remote_apply`.** I set `synchronous_standby_names =
'ebute_replica'` and `synchronous_commit = remote_apply`, then paused replay again.
Finance records the ₦630,000 balance. The INSERT did not return. `pg_stat_activity`
showed the session waiting on `SyncRep`. Three seconds later I resumed replay. The
INSERT returned at 3,077 ms, and the replica had the row at that moment. With this
setting, a commit only returns once the replica can see the data. The price is that every
commit now waits for the replica as well as the primary.

**C. Synchronous when the replica is down.** I stopped the replica and recorded a
payment for order 7. Five seconds later it was still waiting on `SyncRep`, and it would
have waited for ever. My first attempt used `statement_timeout = '5s'` to give up, and
the INSERT waited over a minute anyway. The wait happens at commit, after the statement
timeout has been switched off. In the final version the session is cancelled with
`pg_cancel_backend()`. PostgreSQL then says:

```
WARNING:  canceling wait for synchronous replication due to user request
DETAIL:  The transaction has already committed locally, but might not have been replicated to the standby.
```

The payment was on the primary, even though the application got a warning. When the
replica was started again, it caught up from the replication slot and had the payment
too.

This is the CAP trade-off on two machines. With synchronous replication, losing the
replica stops all writes on the primary. With asynchronous replication, writes carry on,
but a read from the replica can be out of date, and a failover can lose the last few
commits.

**What I would use for Ebute Fresh.** Asynchronous replication, with reads split by how
up to date they need to be:

- On the primary: `confirm_order()` from Portfolio 3, which has to lock lots with
  `FOR UPDATE` and so cannot run on a replica anyway. Also anything a person checks
  straight after changing it, like a payment they have just recorded.
- On the replica: management reports, such as the monthly sales report (Q5) from
  Portfolio 2, and the farmer statement. A few seconds out of date does not matter there,
  and it takes load off the primary.

If losing the last few commits in a failover is not acceptable, the safer set-up is two
replicas with `synchronous_standby_names = 'ANY 1 (replica_a, replica_b)'`. A commit
then waits for either one, so one replica going down does not stop writes. I did not
build that here.

## 03 Failover

The last intake before the failure is lot 20 (Irish potato, Bukuru). The replica was 0
bytes behind. The primary is then stopped with `-m immediate`, which is as close to a
power cut as I can get without one.

- The replica still answers reads (20 lots), but refuses the next intake.
- `SELECT pg_promote()` turns it into a primary. `pg_is_in_recovery()` becomes false and
  the WAL file name shows timeline 2.
- Ijebu-Ode records a plantain intake on the new primary, and it works.
- All 20 lots and all 8 payments (₦8,600,000) from before the crash are there. Nothing
  was lost, because the replica was fully caught up at the time. With asynchronous
  replication that is luck, not a guarantee.

**The new lot is number 52, not 21.** PostgreSQL writes sequence values to WAL 32 at a
time, ahead of use. After a crash or a promotion, the unused ones are skipped. This is the
same as the gaps after a rollback in Portfolio 3: lot numbers are identifiers, not a
count.

**Split brain.** Then the old primary is started again, as someone might do after the
power comes back. It does not know the replica was promoted, so it starts as a primary and
accepts an intake. The result:

```
ebute_primary (port 5440): lots 20=Irish potato, 52=Tomato
ebute_replica (port 5441): lots 20=Irish potato, 52=Plantain
```

Both servers gave out lot 52, for different produce from different centres. If
centres were writing to both, the two databases would drift apart, and there is no
automatic way to merge them. After a failover, the old primary has to be kept off the
network until it has been rebuilt as a replica of the new primary. Rebuilding it could
be done with `pg_rewind`, but that needs `wal_log_hints` or data checksums turned on
before the failure. I did not turn them on, so here the only way back would be to clone
it again with `pg_basebackup`. In a real set-up I would turn on `wal_log_hints` from the
start.

## Sharding

I did not shard the database. The case study does not need it, and sharding would get
in the way of its most important operation.

**Size.** Portfolio 2 generated two years of trading: 600,000 lots, 950,000
allocations and 247,000 orders, in 760 MB. A single server handles that easily, and
the slow report in Portfolio 2 was fixed with a materialised view, not more hardware.

**The obvious shard key does not fit.** The natural split is by collection centre (or
state). Intake, farmers and payouts are all local to a centre, so they would shard
cleanly. But `confirm_order()` fills a line from the oldest lots of a commodity and
grade, wherever they came from. A tomato order could take one lot from Kadawa and the
next from Ogbomoso. With lots sharded by centre, a single order would need locks on
several shards and a two-phase commit, which brings back the lock and failure problems
from Portfolio 3, across a network.

**If the business grew enough to need it,** I would:

- Shard the sales side by `customer_id`, keeping each order, its lines, allocations and
  payments on the same shard.
- Keep lots in a shared stock service, or treat `allocation` as the one place where
  cross-shard work happens.
- Partition `produce_lot` by `received_at` on a single server first. Lots older than a
  few weeks are never allocated again, so old partitions could be moved to cheaper
  storage. That solves the growth problem without distributing transactions.

## Cloud deployment

For production, I would not run my own replica on a laptop. A managed PostgreSQL service
(Amazon RDS for PostgreSQL, Azure Database for PostgreSQL or Google Cloud SQL) provides
the same building blocks:

- **A high-availability standby in another availability zone.** The provider replicates
  to it synchronously and fails over automatically. Importantly, the provider fences
  the old primary, which is exactly the split-brain problem from 03.
- **A read replica** for the management reports, as recommended above.
- **Automated backups and point-in-time recovery.** Replication does not protect against
  a bad UPDATE, because the replica copies the mistake within milliseconds.

Some things to decide before moving to the cloud:

- **Where the data lives.** The database holds farmers' phone numbers and bank account
  numbers, which are personal data under the Nigeria Data Protection Act 2023. The choice
  of region, and whether data can be held outside Nigeria, needs checking against the Act
  before any deployment.
- **Connectivity at the centres.** Kadawa and Zaki Biam are rural. If intake officers
  write directly to a cloud database, a dropped mobile connection stops intake, whatever
  the database's own availability is. The centres need a way to record intakes offline
  and send them when the connection returns. That is an application design issue as much
  as a database one.
- **Security.** This set-up uses `trust` authentication on localhost. A real deployment
  needs SCRAM passwords, TLS on every connection, the replication role limited to the
  replica's address in `pg_hba.conf`, and the database kept off the public internet.

## Limitations

- Both nodes run on one laptop, so there is no real network latency and no real hardware
  failure. The lag in 02 was created by pausing replay, not by a slow link.
- Failover was manual (`pg_promote()`). Nothing detected the failure or redirected the
  applications. In production a tool such as Patroni, or the cloud provider, would do
  both.
- The old primary in 03 was not rejoined to the cluster (see above).
