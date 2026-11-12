# Portfolio 4: NoSQL and Advanced Data Models

This portfolio models Ebute Fresh as documents in MongoDB. I copied the full two-year data
set from Portfolio 2 out of PostgreSQL, and ran the same six queries against it. I also
rebuilt stock reservation from Portfolio 3 as a MongoDB transaction. The aim was to see
where the document model helps this business, and where it makes things harder.

I chose the document model because most of Ebute Fresh's reads are about one thing and
everything attached to it: an order and where its produce came from, or a lot and who
received it. A graph database would also suit traceability (farmer → lot → order →
customer), but recall here is only two steps deep, which documents handle without joins.

## Files

| File | What it does |
|---|---|
| `load-from-postgres.py` / `.out` | Reads the Portfolio 2 data from PostgreSQL, reshapes it into documents, loads MongoDB, and checks the counts |
| `sample-documents.json` | One lot, one order and one farmer, exactly as stored |
| `queries.js` | Q1 to Q6 from Portfolio 2, with plan, documents examined and timing |
| `queries-before-indexes.out`, `queries-after-indexes.out` | Its output before and after `indexes.js` |
| `indexes.js` / `.out` | The four indexes, and their sizes |
| `compare-with-postgres.py` / `.out` | Runs Q1 to Q6 in both databases and checks the answers are identical |
| `validation.js` / `.out` | Schema validation on lots, tested with bad inserts and updates |
| `reserve-stock.js`, `run-reserve.sh`, `reserve-stock.out` | Stock reservation as a multi-document transaction, two sessions at once |

## How to run

MongoDB 9.0 (Homebrew, `mongodb/brew/mongodb-community`), with Python's `pymongo` and
`psycopg2`. Transactions need a replica set, so the server runs as a one-member replica
set:

```
mkdir -p ~/ebute-mongo/data
mongod --dbpath ~/ebute-mongo/data --replSet rs0 --bind_ip localhost --logpath ~/ebute-mongo/mongod.log &
mongosh --eval 'rs.initiate({_id: "rs0", members: [{_id: 0, host: "localhost:27017"}]})'
```

PostgreSQL must hold the Portfolio 2 data (see the Portfolio 2 README). Then, in this
order:

```
cd portfolio-4-nosql
python3 load-from-postgres.py > load-from-postgres.out           # about 70 s
mongosh --quiet ebute_fresh queries.js > queries-before-indexes.out
python3 compare-with-postgres.py > compare-with-postgres.out
mongosh --quiet ebute_fresh indexes.js > indexes.out
mongosh --quiet ebute_fresh queries.js > queries-after-indexes.out
mongosh --quiet ebute_fresh validation.js > validation.out
./run-reserve.sh > reserve-stock.out
```

The order matters. `run-reserve.sh` takes stock from two lots, so Q1 would no longer
match PostgreSQL after it.

## The model

Four collections in place of thirteen tables.

| Collection | One document per | Embedded in it |
|---|---|---|
| `lots` | produce lot | commodity, centre and state, farmer name, receiving officer, payout, and the allocations made from the lot with the customer who got them |
| `orders` | sales order | customer name and type, lines, each line's allocations with the lot's farmer, centre, date and farm-gate price, and payments |
| `farmers` | farmer | home centre, bank details, payouts |
| `customers` | customer | (nothing; full contact details) |

`sample-documents.json` shows real examples. Lot 583326 is one of the lots behind order
240965, so the same allocation can be seen from both sides.

**Embed or reference.** I decided field by field, asking how the data is read and how
often it changes.

- **Commodity, centre and state are copied into each lot.** They are small and almost
  never change. In SQL, every query on lots joined to them.
- **Order lines and payments live inside the order.** They are always read with it, and
  an order has only a few of each.
- **Payouts live inside the farmer.** A farmer is paid at most once a week. After two
  years the farmer with the most payouts has 44, and the largest farmer document is
  4.4 kB, far below MongoDB's 16 MB limit.
- **Customers and farmers have their own collections,** but their names (and the
  customer's phone) are copied wherever they are needed for reading. If Iya Basira Foods
  changes its phone number, the copies in old allocations keep the old one. For a recall
  call list that is wrong, so a phone change would have to update the copies too. This
  is the main cost of the model.
- **Allocations are stored twice.** The order holds where each line came from (Q3, Q5).
  The lot holds who received it (Q4). In SQL, `allocation` was one table read in either
  direction. Here every allocation is written to two documents, which is why reserving
  stock needs a transaction.
- **`best_before` is stored,** not worked out on every read as in the `lot_stock` view.
  It depends only on the receipt date and the commodity's shelf life, neither of which
  changes after intake.

Dates without a time (delivery date, best-before) are stored as midnight UTC, because
BSON has no date-only type. Money is `Decimal128`, not a double, so sums come out to the
naira and kobo.

## Loading and checking the copy

`load-from-postgres.py` loaded 600,018 lots, 246,807 orders, 20,013 farmers and 3,006
customers in about 70 seconds. It then counts every collection and every embedded array
against the matching PostgreSQL table. All nine counts matched, including 949,508
allocations on each side.

| | Documents | Average size | Stored (compressed) |
|---|---|---|---|
| lots | 600,018 | 629 bytes | 96 MB |
| orders | 246,807 | 1,230 bytes | 80 MB |
| farmers | 20,013 | 2,439 bytes | 19 MB |
| customers | 3,006 | 178 bytes | 0.2 MB |

Even with allocations, names and reference data copied, the uncompressed data is about
the same size as the PostgreSQL tables. MongoDB compresses it on disk, so it takes about
195 MB, against 761 MB for the PostgreSQL database.

`compare-with-postgres.py` then ran all six queries against both databases. Every result
was identical, row for row, and so was the total value of all 388,938 order lines
(₦554,449,398,000.00). I did not want to compare speeds until I knew the answers were the
same.

## Queries and indexes

| Query | Before indexes | Docs examined | After indexes | Docs examined | Index |
|---|---|---|---|---|---|
| Q1 tomato A in stock | 135 ms | 600,018 | 0.88 ms | 10 | `lots_in_stock` (partial) |
| Q2 farmer's unpaid lots | 130 ms | 600,018 | 0.61 ms | 34 | `lots_farmer` |
| Q3 trace an order | 0.66 ms | 1 | 0.70 ms | 1 | `_id` |
| Q4 recall | 133 ms | 600,018 | 0.64 ms | 3 | `lots_farmer` |
| Q5 monthly sales | 300 ms | 246,807 | 228 ms | 31,349 | `orders_status_delivery` |
| Q6 near best-before | 192 ms | 600,018 | 1.98 ms | 300 | `lots_best_before` (partial) |

Times are the median of five runs in `mongosh`, so they include the round trip to the
server (about 0.6 ms here). The PostgreSQL times in Portfolio 2 came from EXPLAIN ANALYZE,
which only measures the server. So the small numbers cannot be compared directly, but the
pattern can.

What I noticed:

- **Q3 needed no index and no joins.** In PostgreSQL it joined six tables. Here it reads
  one order document by `_id`. Q4 is the same from the other side: the customers are
  inside the lot. This is what the model was designed for.
- **Without indexes, everything except Q3 reads the whole collection.** The index
  decisions were the same as in Portfolio 2. The partial index trick works here too
  (`partialFilterExpression: {qty_remaining: {$gt: 0}}`). `lots_in_stock` is 48 kB, while
  the full `lots_farmer` index is 9 MB.
- **Q2 still sorts.** `lots_farmer` is ordered by farmer, then commodity, then date, so a
  farmer's lots across all commodities do not come out in date order. With 34 lots that
  does not matter. I kept one index for both Q2 and Q4 instead of adding a second.
- **Q5 hardly improved, just like in PostgreSQL.** The index cut the documents read from
  246,807 to 31,349, but the time only fell from 300 ms to 228 ms. Most of the cost is
  unwinding 125,244 allocations and grouping them, and an index does not help with
  that. In Portfolio 2 the answer was a materialised view. The MongoDB equivalent would be
  a monthly summary collection kept up to date with `$merge`.

## Validation

MongoDB accepts any document unless told otherwise. `validation.js` adds a validator to
`lots` with two parts:

- **`$jsonSchema`:** required fields, grade A/B/C, quantities as whole numbers, stock not
  negative, price a positive decimal.
- **`$expr`:** `qty_remaining` must equal `qty_received` minus the total of the lot's
  allocations.

All 600,018 loaded lots passed. Grade D, negative stock, a missing farmer, a price stored
as text, and a lot whose stock does not match its allocations were all rejected. So was
an update that adds an allocation without reducing `qty_remaining`. An update that does
both in one operation was accepted.

The `$expr` rule is something the relational design did not have. In Portfolio 1,
`qty_remaining` was a stored copy that only a range CHECK protected. Portfolio 3 showed
that the CHECK could not stop a lost update. Here the allocations are inside the lot, so
one rule can check the copy against them.

What MongoDB could not check:

- An allocation to order 999999999, which does not exist, was accepted. There are no
  foreign keys.
- After the accepted updates, order 246807's document still knew nothing about them. A
  validator only sees one document, so it cannot check that the two copies of an
  allocation agree. That is left to the application.

## Reserving stock

`reserve-stock.js` is `confirm_order()` from Portfolio 3, rewritten. It finds the oldest
lots of the right commodity and grade, and takes stock from each with `$inc` and `$push`.
It then writes the allocations and the new status into the order. All of this happens in
one multi-document transaction, so the lot side and the order side change together or not
at all.

`run-reserve.sh` repeats the Portfolio 3 race. Two orders of 30 crates of grade A tomato
are confirmed at the same time. The oldest lot, 597448, has 42 crates.

```
  0.00s   A   confirming order 246808
  0.02s   A   order 246808: lot 597448 shows 42 left, taking 30
  0.02s   A   order 246808: printing delivery note, not committed yet
  0.31s   B   order 246809: lot 597448 shows 42 left, taking 30
  0.32s   B   order 246809: WriteConflict, transaction aborted, retrying
   ... (four more retries)
  1.53s   A   order 246808: COMMIT (attempt 1)
  1.67s   B   order 246809: lot 597448 shows 12 left, taking 12
  1.67s   B   order 246809: lot 597454 shows 44 left, taking 18
  1.68s   B   order 246809: COMMIT (attempt 6)
```

The outcome is the same as Portfolio 3's row-locking demo. Nothing is oversold, B gets
the 12 crates really left plus 18 from the next lot, and lot 597448 ends with 42 allocated
and 0 left. I ran it four times and got the same result each time.

**The difference is how B is held back.** In PostgreSQL, B waited on A's row lock and then
carried on. In MongoDB, B's write to a document A had changed failed straight away with
`WriteConflict`, labelled `TransientTransactionError`. B aborted, waited 250 ms and started
again, five times, until A committed. MongoDB leaves the retry to the application. If two
sales officers keep fighting over the same scarce lot, the work is repeated rather than
queued.

## Is the document model suitable for Ebute Fresh?

**Where it fits:**

- **Traceability and recall.** Q3 and Q4 are single-document reads, with no joins. These
  are the questions that matter most if produce is contaminated.
- **Intake at the centres.** A lot is a natural document. Different commodities could
  carry different quality fields (moisture for onions, size for yams) without changing a
  schema. Portfolio 5 also found that the rural centres need to record intakes offline
  and send them later. Self-contained documents suit that better than rows spread over
  several tables.
- **Storage.** The data takes about a quarter of the disk space.

**Where it does not:**

- **Stock and money.** Every allocation is written twice, and only a transaction keeps
  the copies together. Foreign keys and cross-document rules have to be enforced by
  application code. Under contention, transactions are retried rather than queued.
- **Copied names go stale.** Customer phone numbers inside old lot documents would need
  updating every time a customer changed theirs.
- **Reports.** Q5 is no faster than in SQL.

My conclusion: PostgreSQL should stay the system of record for stock, orders and payments,
where Portfolios 1 and 3 showed its constraints and locking doing real work. A document
store fits alongside it. The centres could capture intakes into it, and it could serve
traceability documents built from PostgreSQL, much as `load-from-postgres.py` does here.

## Limitations

- The loader keeps all allocations in memory while it builds the documents. It peaked at
  about 2.3 GB. For a much larger data set it would need to stream lots and orders in
  `lot_id` and `order_id` order instead.
- The copy is one-off. Keeping MongoDB in step with PostgreSQL would need change data
  capture (for example logical decoding), which I did not build.
- MongoDB runs as a one-member replica set, only so that transactions work. It gives no
  redundancy.
