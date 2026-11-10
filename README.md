# Advanced Database Systems Portfolio

MIT 8103, First Semester 2026/2027. Saleem Jibril.

## Case study: Ebute Fresh Produce Ltd

Ebute Fresh is a simulated produce aggregator based in Lagos. It buys fresh produce
from smallholder farmers at five collection centres and sells it on to restaurants,
supermarkets, caterers and market traders in Lagos.

The centres are Kadawa (Kano), Bukuru (Plateau), Zaki Biam (Benue), Ogbomoso (Oyo)
and Ijebu-Ode (Ogun). Each one specialises in what grows nearby: tomatoes and onions
from Kadawa, Irish potatoes, carrots and cabbage from Bukuru, yams from Zaki Biam, and
so on.

When a farmer brings produce to a centre, an intake officer weighs or counts it,
grades it A, B or C, and records the farm-gate price. That delivery becomes a lot. The
farmer is paid later, usually weekly, for all the lots they delivered. Customers order
by commodity and grade, and the sales desk fills each order from whichever lots have
stock left, oldest first, because most of this produce spoils within days.

**Who uses the database**

- Intake officers at the centres, who record deliveries and grades.
- The sales desk in Lagos, who take orders and allocate stock to them.
- Finance, who pay farmers and record customer payments.
- Management, who need sales, margin and wastage reports.

**Main data stored**

Farmers, collection centres, staff, commodities and their prices, produce lots,
farmer payouts, customers, orders and order lines, stock allocations, and payments.

**Key operations**

- Record an intake and its grade at a centre.
- Pay a farmer for their unpaid lots.
- Place an order and reserve stock against it without overselling.
- Record a customer payment.
- Trace any order line back to the farmers whose produce filled it.
- Report sales by commodity and state, and stock close to its best-before date.

Two things about this business shaped most of the design. Stock is perishable, so the
age of a lot matters as much as its quantity. And several sales staff can be selling
the same scarce lots at the same time, so reserving stock has to be safe under
concurrency.

## Repository layout

```
advanced-database-portfolio/
├── portfolio-1-database-design/
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
├── portfolio-5-distributed-cloud/
└── README.md
```

Each portfolio folder has its own README explaining what was done and how it was
tested.

## Environment

- PostgreSQL 16 on macOS (Homebrew), accessed with `psql`.
