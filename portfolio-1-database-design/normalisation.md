# Normalisation

Before this database, each centre kept an intake spreadsheet and the sales desk kept an
order sheet. I started from those two sheets and normalised them step by step. The
result is the schema in `schema.sql`.

## Starting point: the intake spreadsheet (unnormalised)

One row per farmer visit, typed up by the intake officer:

| Date | Centre | State | Officer | Officer phone | Farmer | Farmer phone | Bank | Account no | Produce | Total due | Paid |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 02/11/26 | Kadawa | Kano | Kabiru Yusuf | 0803 441 7720 | Musa Abdullahi | 0803 662 1904 | Jaiz | 0012348871 | Tomato A x60 @24,000 | 1,440,000 | 06/11 FT..118 |
| 28/10/26 | Kadawa | Kano | Kabiru Yusuf | 0803 441 7720 | Musa Abdullahi | 0803 662 1904 | Jaiz | 0012348871 | Tomato B x20 @19,000; Rodo B x12 @28,000 | 716,000 | 30/10 FT..041 |
| 02/11/26 | Bukuru | Plateau | Joseph Dung | 0806 551 2093 | Danjuma Gyang | 0806 559 0318 | First Bank | 3110590318 | Irish potato A x40 @38,000 | 1,520,000 | 06/11 FT..121 |

Problems with it:

- The Produce column holds a list. You cannot sum crates of tomato across farmers
  without splitting text.
- Farmer and officer details are retyped on every visit. When a farmer changes bank,
  old rows still show the old account, and nobody knows which is right.
- "Rodo" on one sheet is "Scotch bonnet" or "Pepper" on another.
- Total due is calculated by hand and can be wrong.
- There is no way to say which customer order a crate went to.

## First normal form

Each cell holds one value and there are no repeating groups. The Produce list is split
so that each commodity and grade in a visit becomes its own row, and the quantity and
price get their own columns. Total due is dropped because it is a calculation.

INTAKE(**date, farmer_phone, commodity, grade**, centre, state, officer, officer_phone,
farmer_name, bank, account_no, unit, qty, farm_gate_price, paid_date, bank_ref)

The key is shown in bold. A farmer can bring the same commodity in two grades on one
visit, so commodity alone is not enough; grade has to be in the key.

## Second normal form

2NF removes partial dependencies, where a column depends on only part of the composite
key. In INTAKE:

| Dependency | Part of the key it depends on |
|---|---|
| farmer_name, bank, account_no | farmer_phone |
| unit | commodity |
| centre, officer | date, farmer_phone (where the farmer delivered that day) |
| paid_date, bank_ref | date, farmer_phone (one payment covers the visit) |
| qty, farm_gate_price | the whole key |

Splitting these out gives:

- FARMER(**farmer_phone**, farmer_name, bank, account_no)
- COMMODITY(**commodity**, unit)
- VISIT(**date, farmer_phone**, centre, state, officer, officer_phone, paid_date, bank_ref)
- LOT(**date, farmer_phone, commodity, grade**, qty, farm_gate_price)

## Third normal form

3NF removes transitive dependencies, where a non-key column depends on another non-key
column.

- In VISIT, centre → state and officer → officer_phone. These move to
  COLLECTION_CENTRE(centre, state) and STAFF(officer, officer_phone, centre).
- Payment details depend on the payment, not on the visit. In practice finance pays a
  farmer once a week for several visits, so this is really a separate entity:
  FARMER_PAYOUT(bank_ref, farmer, amount, paid_date), with each lot pointing to the
  payout that settled it.
- State name was a free-text column. It becomes STATE(state_code, state_name).

After this step I made two changes that are about keys rather than normal forms:

1. **Surrogate keys.** Phone numbers change and dates are not unique, so FARMER, STAFF
   and LOT get generated IDs. The phone number stays as a UNIQUE column, so it is still
   a candidate key.
2. **The VISIT table was dropped.** Once payment moved to FARMER_PAYOUT, a visit only
   held the centre and the officer. Nothing in the business refers to a visit; orders,
   allocations and payouts all refer to lots. So the centre and officer moved onto the
   lot, and the lot became the unit of intake. This is discussed again under the
   deliberate departures below.

## The order sheet

The sales desk sheet had the same kind of problems: customer details repeated on every
order, several items in one cell ("Tomato A 30cr, Irish A 10 bags, carrot 8"), and a
"lots used" column that was usually blank. Working through the same steps gave:

- CUSTOMER, with phone and email as candidate keys alongside customer_id.
- SALES_ORDER(order_id, customer_id, taken_by, placed_at, delivery_date, status).
- ORDER_LINE(order_id, line_no, commodity, grade, quantity, unit_price).
- ALLOCATION(order_id, line_no, lot_id, quantity). The "lots used" column was a
  many-to-many relationship hidden in one cell. As a table it can record that 35 crates
  for Kemi's Events came 30 from lot 1 and 5 from lot 14.
- PAYMENT(payment_id, order_id, amount, method, reference). One order can be paid in
  parts, which the sheet could not show.

## BCNF check

BCNF requires every determinant to be a candidate key. I went through each table:

| Table | Determinants | Candidate keys | BCNF? |
|---|---|---|---|
| state | state_code, state_name | both | yes |
| collection_centre | centre_id, centre_name | both | yes |
| staff | staff_id, phone | both | yes |
| farmer | farmer_id, phone | both | yes |
| commodity | commodity_id, commodity_name | both | yes |
| commodity_price | (commodity_id, grade, effective_from) | that one | yes |
| farmer_payout | payout_id, bank_ref | both | yes |
| customer | customer_id, phone, email | all three | yes |
| sales_order | order_id | order_id | yes |
| order_line | (order_id, line_no), (order_id, commodity_id, grade) | both | yes |
| allocation | (order_id, line_no, lot_id) | that one | yes |
| payment | payment_id, reference | both | yes |
| produce_lot | lot_id, received_by | lot_id only | **no**, see below |

order_line is worth a note. A line is identified by its line number, but the UNIQUE
constraint on (order_id, commodity_id, grade) also makes that a candidate key, because
the sales desk never puts the same commodity and grade on two lines of one order. Both
determinants are keys, so it is in BCNF.

## Deliberate departures

There are three places where I kept data that could be derived. Each is protected by a
constraint so it cannot drift out of step.

**1. produce_lot.centre_id.** An intake officer works at one centre, so
received_by → centre_id, which is a transitive dependency and breaks 3NF. I kept
centre_id on the lot because almost every stock and sales report groups by centre or
state, and it saves a join through staff on the largest table. The composite foreign
key (received_by, centre_id) → staff(staff_id, centre_id) means the two can never
disagree; constraint tests 4 and 5 show this.

The cost is that an officer with lots on record cannot be moved to another centre,
because changing staff.centre_id would break the foreign key on their old lots. This
has not happened yet at Ebute Fresh. If it does, the fix would be a staff_posting table
with dates, and the lot would reference the posting instead.

**2. produce_lot.qty_remaining.** This equals qty_received minus the sum of the lot's
allocations, so in theory it should not be stored. I kept it for two reasons:

- The sales desk asks "what grade A tomato is left?" many times a day. Without the
  column, every check sums the allocation table.
- In Portfolio 3, reserving stock locks the lot row and decrements qty_remaining. The
  CHECK (qty_remaining BETWEEN 0 AND qty_received) then makes overselling impossible at
  the database level, even if two sales staff try at the same moment. A derived value
  cannot be locked in the same way.

Constraint test 20 confirms it matches the allocations in the sample data.

**3. farmer_payout.amount.** This could be calculated from the lots it settles. I store
it because it is the amount that actually left the bank account, and finance needs to
see that figure even if a lot is later corrected. Test 23 checks they agree.

Two other columns look redundant but are not:

- **order_line.unit_price** is not a copy of commodity_price. It is the price agreed
  with the customer on the day. Order 4 was taken at ₦38,000 a crate before the
  7 November rise to ₦42,000, and must stay at ₦38,000.
- **best_before** is not stored at all. It depends only on received_at and the
  commodity's shelf_life_days, so the lot_stock view works it out when needed.
