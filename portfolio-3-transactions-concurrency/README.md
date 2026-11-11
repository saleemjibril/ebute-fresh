# Portfolio 3: Transactions and Concurrency

The operation in the case study most at risk from concurrency is reserving stock. Several
people on the sales desk sell from the same few lots, and a tomato lot can be gone in a
morning. This portfolio shows how Ebute Fresh reserves stock safely, and what goes wrong
without it.

## Files

| File | What it shows |
|---|---|
| `confirm-order.sql` | `confirm_order()`, which reserves stock for an order, oldest lot first |
| `setup.sql` | Resets the database to the Portfolio 1 sample week plus two new orders |
| `01-commit.sql` / `.out` | A transaction that commits |
| `02-rollback.sql` / `.out` | Explicit rollback, rollback after an error, and savepoints |
| `03-lost-update-a.sql`, `-b.sql`, `.out` | Two sessions oversell a lot (the problem) |
| `04-row-locking-a.sql`, `-b.sql`, `.out` | The same two sessions using row locks (the fix) |
| `05-isolation-a.sql`, `-b.sql`, `.out` | READ COMMITTED against REPEATABLE READ |
| `06-deadlock-a.sql`, `-b.sql`, `.out` | A deadlock, and how lock ordering prevents it |
| `run-pair.sh` | Runs a two-session demo and merges both outputs into one timeline |

## How to run

```
cd portfolio-3-transactions-concurrency
psql -d ebute_fresh -q -f setup.sql && psql -d ebute_fresh -e -f 01-commit.sql > 01-commit.out 2>&1
psql -d ebute_fresh -q -f setup.sql && psql -d ebute_fresh -e -f 02-rollback.sql > 02-rollback.out 2>&1
./run-pair.sh 03-lost-update
./run-pair.sh 04-row-locking
./run-pair.sh 05-isolation
./run-pair.sh 06-deadlock
```

`setup.sql` rebuilds the Portfolio 1 schema and sample data, so each demo starts from
the same state. This removes the large Portfolio 2 data set. The commands in the
Portfolio 2 README rebuild it.

The starting state matters for the demos. On the morning of 10 November, grade A tomato
is down to two lots: lot 14 (25 crates left) and lot 19 (40 crates, just arrived). Two
orders are waiting: order 8 for 20 crates and order 9 for 15 crates.

## How the two-session demos work

Two `psql` connections start at the same moment. `pg_sleep()` in each script sets the
order of events. Every step prints a line with `clock_timestamp()`, and `run-pair.sh`
merges the two outputs by time. A wait shows up as a gap: in 04, session B calls
`confirm_order(9)` at 0.52 s and nothing comes back until A commits at 2.04 s.

I ran each two-session demo four times. The timings moved by a few milliseconds, but
the outcomes were identical every time.

## confirm_order()

For each order line it loops through the lots of that commodity and grade that still
have stock, oldest first. From each lot it takes what it needs, records an allocation and
reduces `qty_remaining`, until the line is filled. If a line cannot be filled it raises
an error. Since it runs inside the caller's transaction, the error undoes everything it
did, including lines it had already filled.

It controls concurrency in three ways:

1. **It locks the order row first**, so the same order cannot be confirmed twice at
   once. A second attempt on a confirmed order is refused (end of 01).
2. **It locks each lot with `SELECT ... FOR UPDATE` before taking from it.** Anyone else
   who wants that lot waits until the first transaction ends, then reads the new
   quantity.
3. **It handles lines in commodity and grade order, not the order they were typed.**
   This means any two orders always lock lots in the same sequence, which rules out
   deadlocks between them.

## What each demo shows

**01 Commit.** Order 7 is confirmed: 150 yam from lot 8 and 4 bags of scotch bonnet
from lot 10. Inside the transaction, the allocations are already visible to the session
making them. After COMMIT they are permanent. The lots are reduced and the order is
marked confirmed, all as one unit.

**02 Rollback.**
- *Explicit rollback (2a).* An order is entered and then abandoned. After ROLLBACK,
  neither the order nor its line exists.
- *Error rollback (2b).* An order asks for 100 crates of grade A tomato when only 65
  exist. `confirm_order()` allocates all 65, then hits the shortfall and raises an error.
  PostgreSQL refuses any further statement in that transaction until it is rolled back.
  Afterwards the order, the 65 crates of allocations and the stock changes are all gone,
  and lots 14 and 19 still show 25 and 40.
- *Savepoints (2c).* The Friday payout run pays three farmers in one transaction, with
  a savepoint for each. Farmer 10's bank reference is mistyped as one already used, which
  breaks the UNIQUE constraint. Rolling back to that savepoint undoes only farmer 10;
  farmers 12 and 2 are paid when the transaction commits.
- *Sequences are not rolled back.* The order in 2b is numbered 11, not 10, because 2a
  used 10 before rolling back. The payouts in 2c are 8 and 10, because the failed one
  used 9. This is expected in PostgreSQL. It is why the sample-data IDs can have gaps,
  and why IDs should not be used as a count of anything.

**03 Lost update (the problem).** This uses the naive application approach: read
`qty_remaining`, work out the new figure, write it back.

```
  0.01s   A   reads lot 14: 25 crates left
  0.54s   B   reads lot 14: 25 crates left
  1.04s   A   allocates 20 crates to order 8, sets lot 14 to 5
  1.04s   A   COMMIT
  1.56s   B   allocates 15 crates to order 9, sets lot 14 to 10
  1.56s   B   COMMIT
  1.87s   B   RESULT lot 14: received 50, allocated in total 60, qty_remaining says 10
```

B overwrote A's update. 60 crates were promised from a 50-crate lot, and the stock
figure says 10 are still left. The CHECK constraint from Portfolio 1 did not help,
because 10 is a perfectly valid value. Constraints check each row on its own; they
cannot see that two transactions have both used the same crates.

**04 Row locking (the fix).** The same two orders, using `confirm_order()`:

```
  0.01s   A   confirm_order(8) done: took 20 crates from lot 14, not committed yet
  0.52s   B   calls confirm_order(9) ...
  1.04s   A   sees session 3495 waiting on Lock/transactionid: SELECT confirm_order(9);
  2.04s   A   COMMIT
  2.05s   B   confirm_order(9) done: took 5 crates from lot 14
  2.05s   B   confirm_order(9) done: took 10 crates from lot 19
```

B blocks on lot 14 until A commits. `pg_stat_activity` shows it waiting on A's
transaction ID. When it continues, it sees the 5 crates that are really left, takes
them, and gets the other 10 from lot 19. Nothing is oversold, and the oldest stock still
goes first.

In this version, the CHECK constraint is the second line of defence. If the code had
used an atomic `UPDATE ... SET qty_remaining = qty_remaining - 15` without the lock,
B's update would have waited for A as well, then re-checked the row and found it would
go to -10. The CHECK would have rejected that. So the database would still not oversell,
but the sales officer would get an error instead of being given the next lot.

**05 Isolation levels.** Finance reads the grade A tomato stock twice in one
transaction while sales confirm orders in between.

- **READ COMMITTED:** the two reads disagree, 65 and then 45. Each statement sees
  whatever had been committed when that statement started. This is a non-repeatable
  read.
- **REPEATABLE READ:** both reads say 45, even though order 9 committed between them.
  The transaction works from one snapshot, taken at its first query. A new transaction
  afterwards sees 30.

For a report whose figures have to add up, REPEATABLE READ is the right choice. For
`confirm_order()`, I kept the default READ COMMITTED. With FOR UPDATE, a transaction
that waited for a lock goes on with the latest version of the row, which is exactly
what 04 needs. Under REPEATABLE READ, PostgreSQL does not allow that. B would have
failed with a serialisation error, and the application would need to retry the whole
order.

**06 Deadlock.** Two orders each need tomato and plantain, typed in opposite orders.

```
  0.00s   A   locked lot 14 (tomato)
  0.52s   B   locked lot 12 (plantain)
  1.00s   A   asks for lot 12 (plantain) ...
  1.53s   B   asks for lot 14 (tomato) ...
  2.08s   A      ERROR:  deadlock detected
  2.08s   A   was rolled back by PostgreSQL to break the deadlock, so lot 14 is released
  2.08s   B   locked lot 14 (tomato)
```

Each session holds the lot the other one wants. PostgreSQL checks for deadlocks after a
wait of `deadlock_timeout` (1 second). A had been waiting longest, so it found the cycle
and was rolled back. In round 2 both sessions lock tomato before plantain. B simply
waits for A to finish, and nobody is rolled back. That is why `confirm_order()` sorts
lines by commodity and grade.

## Limitations

- Locking a lot holds it until the transaction ends. In 04, B waited the whole time A
  spent "printing the delivery note". In practice that step should happen after COMMIT,
  so locks are held for milliseconds. `FOR UPDATE SKIP LOCKED` would let B take the next
  lot instead of waiting, but it would break the oldest-first rule, so I did not use it.
- The deadlock demo uses plain `SELECT ... FOR UPDATE` statements rather than
  `confirm_order()`. The function finishes too quickly to catch it in the middle of an
  order. The demo shows the locking pattern; the function applies the ordering rule.
