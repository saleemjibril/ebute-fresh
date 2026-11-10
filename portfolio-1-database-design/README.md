# Portfolio 1: Database Design and Modelling

Relational design for Ebute Fresh Produce (see the main README for the case study).

## Files

| File | What it is |
|---|---|
| `er-diagram.md` / `er-diagram.png` | ER diagram with keys, cardinalities and notes on each relationship |
| `schema.sql` | The 13 tables, keys, constraints, one trigger and one view |
| `normalisation.md` | From the centres' spreadsheets to 3NF/BCNF, and where I chose not to normalise |
| `sample-data.sql` | One week of trading, 2 to 9 November 2026 |
| `constraint-tests.sql` | Statements that should fail, and consistency checks on the data |
| `constraint-tests.out` | Output from running the tests |

## How to run it

```
createdb ebute_fresh
psql -d ebute_fresh -f schema.sql -f sample-data.sql
psql -d ebute_fresh -e -f constraint-tests.sql > constraint-tests.out 2>&1
```

`schema.sql` drops everything first, so it can be re-run to start clean.

## Design decisions

**Entities.** The centre of the design is the produce lot: one delivery of one commodity
and grade by one farmer. Everything else hangs off it. Intake creates lots, payouts
settle lots, and orders are filled from lots through `allocation`.

**Keys.** Every main table has a generated identity key, because the natural candidates
(phone numbers, names, dates) either change or repeat. Where a natural key does exist it
is kept as UNIQUE: phone numbers, bank references, commodity names. Three tables use
composite keys because their rows only make sense as part of something else:
`commodity_price` (commodity, grade, date), `order_line` (order, line number) and
`allocation` (order, line, lot).

**Constraints.** I tried to put the business rules in the database rather than leave
them to whoever writes the application:

- Grades and phone numbers are domains, so the same rule applies in every table that
  uses them.
- `qty_remaining` must stay between 0 and `qty_received`. This is what stops a lot
  being oversold.
- Only an intake officer can receive a lot, and only at their own centre (composite
  foreign key to `staff`).
- A lot can only be paid through a payout for the same farmer (composite foreign key to
  `farmer_payout`).
- Transfers and POS payments need a reference; cash does not.
- Bank details are all or nothing.
- An allocated lot must be the same commodity and grade as the order line. A foreign key
  cannot express this, so it is the one rule done with a trigger.

**Delete behaviour.** Order lines and allocations cascade when an order is deleted,
because they mean nothing without it. Everything else uses the default (no action), so
you cannot delete a farmer, customer or lot that other records point to. Test 19 shows
this.

**Indexes.** Only the indexes that come with primary keys and UNIQUE constraints exist
at this stage. Foreign key columns are left unindexed on purpose so that Portfolio 2 can
measure the difference.

The reasons for the three stored values that could be derived (`centre_id` and
`qty_remaining` on lots, and payout amounts) are in `normalisation.md`.

## Testing

`constraint-tests.sql` has two parts.

Part 1 is 19 statements that break a rule: grade D, overselling a lot, an officer
recording intake at the wrong centre, a sales person recording intake, paying one
farmer's lot through another farmer's payout, a duplicate phone number, a transfer with
no reference, a yam lot allocated to a tomato order, deleting a farmer with history, and
so on. All 19 were rejected, each by the constraint it was aimed at. The error messages
are in `constraint-tests.out`.

Part 2 runs six queries over the sample data that should return nothing if the data is
consistent: lot balances match allocations, confirmed and delivered orders are fully
allocated, pending and cancelled orders hold no stock, payouts equal the value of their
lots, no order is overpaid, and no lot was used before it arrived. All six returned
0 rows.

The file ends with a summary of what each customer still owes, as a check that the
order and payment data join up correctly.

## Limitations

- An order should have at least one line. That cannot be enforced with a plain
  constraint, so it depends on the order and its lines being inserted in one
  transaction.
- An intake officer cannot be moved to a different centre once they have lots on
  record (explained in `normalisation.md`).
- The sample data is small. Portfolio 2 adds a much larger generated data set for the
  performance work.
