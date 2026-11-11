# Performance analysis

## Set-up

- PostgreSQL 16.15 on an Apple M1 Pro with 16 GB of RAM, default settings
  (shared_buffers 128 MB, work_mem 4 MB).
- Data from `generate-data.sql`: 600,018 lots, 246,807 orders, 388,938 order lines,
  949,508 allocations and 466,256 payouts. produce_lot is the largest table at
  154 MB (19,738 pages).
- Each query was run once to warm the cache, then measured with
  `EXPLAIN (ANALYZE, BUFFERS)`. I repeated the full set five times in each state and
  the medians were within a few milliseconds of the saved figures.

## Results

Times are execution times from `plans-before.txt` and `plans-after.txt`. Pages are the
8 kB buffers each query touched.

| Query | Before | After | Pages before | Pages after | Index used |
|---|---|---|---|---|---|
| Q1 stock, oldest first | 27.3 ms | 0.09 ms | 20,092 | 17 | produce_lot_in_stock_idx |
| Q2 farmer's unpaid lots | 29.5 ms | 0.04 ms | 19,861 | 10 | produce_lot_farmer_idx |
| Q3 order back to farmers | 0.15 ms | 0.16 ms | 102 | 102 | primary keys only |
| Q4 recall, farmer to customers | 53.7 ms | 0.08 ms | 26,854 | 52 | produce_lot_farmer_idx, allocation_lot_idx |
| Q5 quarterly sales report | 182.0 ms | 185.8 ms | 31,824 | 31,664 | sales_order_delivery_idx (small part) |
| Q6 stock near best-before | 24.0 ms | 1.7 ms | 19,928 | 820 | produce_lot_in_stock_idx |

## What the plans show

**Q1, Q2 and Q6 were all full scans of produce_lot.** Each read all 600,000 lots to keep
a handful: 183 rows for Q1, 2 for Q2, and 2,593 for Q6. PostgreSQL split the scan
across two parallel workers, which is why each took about 25 to 30 ms rather than
longer. The cost is the same whatever the answer, and it grows with the table.

**The partial index did most of the work.** Only about 2,600 lots have stock left at any
time, and those are the only lots the sales desk cares about. An index with
`WHERE qty_remaining > 0` covers just those rows, so it is 96 kB against 33 MB for
the primary key. Because the key ends in `received_at`, Q1 reads its first ten rows
already in date order and stops. The Sort node from the old plan is gone. Q6 uses the same index
as a bitmap scan to fetch the 2,593 lots with stock, then works out best-before on
them. Q6 cannot use an index on best-before itself, because it is calculated from
received_at plus the commodity's shelf life, which lives in another table. Making the
candidate set small was the practical way round that.

**Q3 was already fast**, and that is down to the design in Portfolio 1. Every join in
it follows a primary key, including allocation's (order_id, line_no, lot_id).
**Q4 is the same trace in reverse**, and it was the slowest of the small queries for a
reason that is easy to miss. The allocation primary key exists, but it starts with
order_id, so it is useless for finding rows by lot_id. The plan shows a full parallel
scan of all 949,508 allocations. A separate index on allocation(lot_id) took it from
53.7 ms to 0.08 ms. Column order in a composite key decides which lookups it can
serve.

**Q5 did not improve, and should not have.** The new index on delivery_date is used to
pick out the quarter's orders, but that step was about 5 ms of the total. The rest is
joining around 125,000 allocations to their lots, which is 13% of the allocation table.
For that much data, reading the tables straight through and hash joining is cheaper
than 125,000 separate index lookups.

I tested this in `q5-experiments.sql` by switching off hash joins, merge joins and
sequential scans so the planner had to use indexes. The query took 668 ms, 3.6 times
slower. The planner's choice was right.

What does help a report like this is not recomputing it. Delivered orders do not change
once a month is over, so I stored the monthly totals in a materialised view. The report
then reads 36 rows and runs in 0.06 ms. The cost moves to the refresh, which took
0.6 seconds for two years of data and can run overnight. With `CONCURRENTLY`, reports
can still read the old figures while it runs. I checked that the view's figures match
the original query exactly, and they do. The trade-off is that the report is only as
fresh as the last refresh, which is acceptable for a monthly management report but
would not be for stock levels.

## Costs of the indexes

- **Space.** The four indexes add about 24 MB. Nearly all of that is
  allocation_lot_idx (18 MB), because allocation is the longest table.
- **Writes.** Every allocation insert now also updates allocation_lot_idx. The partial
  index has a less obvious cost. Its condition uses qty_remaining, so each time stock is
  taken from a lot, PostgreSQL cannot do a HOT (heap-only) update and has to write
  index entries again. Taking stock is the most frequent write in the system. I think
  the trade is still worth it, because reading available stock happens even more often
  than reserving it, but this is the index I would watch first if intake or ordering
  slowed down.
- **The index on sales_order.delivery_date was barely needed.** The step it serves went
  from about 5 ms to 3.7 ms, on a report that now uses the materialised view instead. I kept it because the sales
  desk also looks up the day's deliveries, but on these results alone it would not
  justify itself.

## Other observations

- In the before plans, most pages show as `read`, not `hit`. produce_lot (154 MB) is
  bigger than shared_buffers (128 MB), and PostgreSQL deliberately reads large
  sequential scans through a small ring buffer so that one scan cannot push everything
  else out of the cache. The pages were coming from the operating system's cache, which
  is why the times are still in milliseconds.
- While generating the data I hit a planner problem of my own making. A staging column
  for grade was `text` while the real column is the `produce_grade` domain, so the
  join compared `grade::text` and could not use the index. The allocation insert ran
  for over ten minutes before I cancelled it. With the cast fixed it took a few
  seconds. Data types on both sides of a join need to match for an index to be usable.
