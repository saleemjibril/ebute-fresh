# Portfolio 2: Query Processing and Optimisation

Six queries from the Ebute Fresh case study, their execution plans on two years of
generated data, and the effect of indexing them.

## Files

| File | What it is |
|---|---|
| `generate-data.sql` / `.out` | Builds two years of trading history on top of the Portfolio 1 sample week |
| `queries.sql` | The six queries |
| `query-results.txt` | Their results |
| `run-plans.sh` | Captures `EXPLAIN (ANALYZE, BUFFERS)` for all six queries |
| `plans-before.txt` | Plans with only the Portfolio 1 keys |
| `indexes.sql` / `.out` | The four indexes added, and their sizes |
| `plans-after.txt` | Plans with the new indexes |
| `q5-experiments.sql` / `.out` | Forcing an index plan for Q5, and a materialised view instead |
| `performance-analysis.md` | Results and discussion |

## The queries

Each query is one of the key operations listed in the main README.

| | Query | Who runs it |
|---|---|---|
| Q1 | Grade A tomato with stock left, oldest first | Sales desk, every order |
| Q2 | A farmer's unpaid lots | Finance, Friday payout run |
| Q3 | Trace an order back to the farmers who supplied it | Sales desk, customer queries |
| Q4 | Recall: which customers got a farmer's tomatoes in a fortnight | Management, food safety |
| Q5 | Sales and margin by month, commodity and source state for a quarter | Management |
| Q6 | Stock reaching its best-before date in the next two days | Sales desk, daily |

## How to reproduce

```
cd portfolio-2-query-optimisation
psql -d ebute_fresh -f ../portfolio-1-database-design/schema.sql \
                    -f ../portfolio-1-database-design/sample-data.sql
psql -d ebute_fresh -f generate-data.sql > generate-data.out 2>&1   # about a minute
psql -d ebute_fresh -f queries.sql > query-results.txt
./run-plans.sh plans-before.txt
psql -d ebute_fresh -f indexes.sql > indexes.out
./run-plans.sh plans-after.txt
psql -d ebute_fresh -f q5-experiments.sql > q5-experiments.out 2>&1
```

`generate-data.sql` uses a fixed random seed, so it produces the same data each time.

## How the test data was made

The generated data had to obey every rule from Portfolio 1, or the plans would be for a
database that could not exist. 20,000 farmers deliver 600,000 lots to their own centre,
and each centre only handles the produce it actually gets (no yams at Kadawa). Prices
follow a monthly price list that rises about 2% a month.

Orders are filled the way the sales desk does it, oldest lot first. Lots and order lines
are each laid end to end as running totals per commodity and grade, and where a line's
range overlaps a lot's range, that overlap becomes an allocation. Line quantities are
sized from what had arrived two days before delivery, which is roughly the time it takes
to get produce to Lagos.

My first version sized orders independently of supply, and 17% of allocations used a
lot that arrived after the order was delivered. Plantain was the worst, because
Ijebu-Ode only opened in March 2025, but every commodity had some.

After generating, I re-ran the Portfolio 1 consistency checks on the full data set. All
of them return 0 rows:
- every lot balance matches its allocations
- every delivered line is fully allocated
- every payout equals its lots
- every allocation's commodity and grade match its order line
- no lot is used before it arrives

The allocation trigger is switched off for the bulk insert, because it checks each row
individually and every row is correct by construction. It is switched back on in the
same transaction.

## Summary of results

Indexes made Q1, Q2, Q4 and Q6 between 14 and 690 times faster. Q3 was already fast
because it only follows primary keys. Q5 did not improve, and forcing it to use indexes
made it 3.6 times slower. A materialised view fixed it instead. Full figures and
discussion are in `performance-analysis.md`.
