-- Ebute Fresh Produce Ltd: relational schema
-- PostgreSQL 16
--
-- Run against an empty database:
--   createdb ebute_fresh
--   psql -d ebute_fresh -f schema.sql
--
-- Foreign key columns are deliberately left without indexes here.
-- Portfolio 2 measures queries before and after adding them.

DROP TABLE IF EXISTS payment, allocation, order_line, sales_order, customer,
                     produce_lot, farmer_payout, commodity_price, commodity,
                     farmer, staff, collection_centre, state CASCADE;
DROP VIEW IF EXISTS lot_stock;
DROP DOMAIN IF EXISTS produce_grade, ng_phone;


-- Grades are given at intake. A is export/supermarket quality, C is for
-- processors and market traders.
CREATE DOMAIN produce_grade AS char(1)
    CHECK (VALUE IN ('A', 'B', 'C'));

-- Phone numbers are stored in international form, e.g. +2348031234567.
CREATE DOMAIN ng_phone AS varchar(14)
    CHECK (VALUE ~ '^\+234[789][01][0-9]{8}$');


CREATE TABLE state (
    state_code  char(2)     PRIMARY KEY,
    state_name  varchar(30) NOT NULL UNIQUE
);

CREATE TABLE collection_centre (
    centre_id    smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    centre_name  varchar(40) NOT NULL UNIQUE,
    town         varchar(40) NOT NULL,
    state_code   char(2)     NOT NULL REFERENCES state,
    opened_on    date        NOT NULL
);

-- Intake officers work at one centre. Sales, finance and management are
-- based in Lagos and have no centre.
CREATE TABLE staff (
    staff_id   integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name  varchar(80) NOT NULL,
    role       varchar(20) NOT NULL
               CHECK (role IN ('intake_officer', 'sales', 'finance', 'manager')),
    centre_id  smallint    REFERENCES collection_centre,
    phone      ng_phone    NOT NULL UNIQUE,
    CHECK ((role = 'intake_officer') = (centre_id IS NOT NULL)),
    -- lets produce_lot check that an officer belongs to the centre
    UNIQUE (staff_id, centre_id)
);

CREATE TABLE farmer (
    farmer_id       integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name      varchar(40) NOT NULL,
    last_name       varchar(40) NOT NULL,
    phone           ng_phone    NOT NULL UNIQUE,
    home_centre_id  smallint    NOT NULL REFERENCES collection_centre,
    bank_name       varchar(40),
    account_number  char(10)    CHECK (account_number ~ '^[0-9]{10}$'),
    registered_on   date        NOT NULL DEFAULT current_date,
    -- bank details are optional, but must be complete if given
    CHECK ((bank_name IS NULL) = (account_number IS NULL))
);

CREATE TABLE commodity (
    commodity_id     smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    commodity_name   varchar(30) NOT NULL UNIQUE,
    unit             varchar(10) NOT NULL
                     CHECK (unit IN ('crate', 'bag', 'tuber', 'bunch')),
    shelf_life_days  smallint    NOT NULL CHECK (shelf_life_days > 0)
);

-- Selling prices change often, so they are kept with the date they took
-- effect. The current price is the latest row on or before today.
CREATE TABLE commodity_price (
    commodity_id    smallint      NOT NULL REFERENCES commodity,
    grade           produce_grade NOT NULL,
    effective_from  date          NOT NULL,
    selling_price   numeric(10,2) NOT NULL CHECK (selling_price > 0),
    PRIMARY KEY (commodity_id, grade, effective_from)
);

-- One payout settles one or more lots for a single farmer.
CREATE TABLE farmer_payout (
    payout_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    farmer_id  integer       NOT NULL REFERENCES farmer,
    amount     numeric(12,2) NOT NULL CHECK (amount > 0),
    paid_at    timestamptz   NOT NULL DEFAULT now(),
    bank_ref   varchar(30)   NOT NULL UNIQUE,
    paid_by    integer       NOT NULL REFERENCES staff,
    -- lets produce_lot check that a payout belongs to the lot's farmer
    UNIQUE (payout_id, farmer_id)
);

-- A lot is one delivery of one commodity and grade by one farmer.
-- qty_remaining is derivable from allocations; it is stored on purpose
-- (see normalisation.md) and kept in range by the CHECK below.
CREATE TABLE produce_lot (
    lot_id           bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    farmer_id        integer       NOT NULL REFERENCES farmer,
    centre_id        smallint      NOT NULL REFERENCES collection_centre,
    commodity_id     smallint      NOT NULL REFERENCES commodity,
    grade            produce_grade NOT NULL,
    qty_received     integer       NOT NULL CHECK (qty_received > 0),
    qty_remaining    integer       NOT NULL,
    farm_gate_price  numeric(10,2) NOT NULL CHECK (farm_gate_price > 0),
    received_at      timestamptz   NOT NULL DEFAULT now(),
    received_by      integer       NOT NULL,
    payout_id        bigint,
    CHECK (qty_remaining BETWEEN 0 AND qty_received),
    -- the receiving officer must work at this centre
    FOREIGN KEY (received_by, centre_id) REFERENCES staff (staff_id, centre_id),
    -- a lot can only be paid through its own farmer's payout
    FOREIGN KEY (payout_id, farmer_id) REFERENCES farmer_payout (payout_id, farmer_id)
);

CREATE TABLE customer (
    customer_id    integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_name  varchar(80)  NOT NULL,
    customer_type  varchar(12)  NOT NULL
                   CHECK (customer_type IN ('restaurant', 'supermarket', 'caterer', 'trader')),
    contact_name   varchar(80)  NOT NULL,
    phone          ng_phone     NOT NULL UNIQUE,
    email          varchar(120) UNIQUE,
    address        varchar(160) NOT NULL,
    lga            varchar(30)  NOT NULL
);

CREATE TABLE sales_order (
    order_id       bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    integer     NOT NULL REFERENCES customer,
    taken_by       integer     NOT NULL REFERENCES staff,
    placed_at      timestamptz NOT NULL DEFAULT now(),
    delivery_date  date        NOT NULL,
    status         varchar(10) NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'confirmed', 'delivered', 'cancelled'))
);

-- unit_price is the price agreed when the order was taken, which can
-- differ from commodity_price later on.
CREATE TABLE order_line (
    order_id      bigint        NOT NULL REFERENCES sales_order ON DELETE CASCADE,
    line_no       smallint      NOT NULL CHECK (line_no > 0),
    commodity_id  smallint      NOT NULL REFERENCES commodity,
    grade         produce_grade NOT NULL,
    quantity      integer       NOT NULL CHECK (quantity > 0),
    unit_price    numeric(10,2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, line_no),
    UNIQUE (order_id, commodity_id, grade)
);

-- Which lots filled which order line. This resolves the many-to-many
-- between order lines and lots, and is what makes traceability possible.
CREATE TABLE allocation (
    order_id  bigint   NOT NULL,
    line_no   smallint NOT NULL,
    lot_id    bigint   NOT NULL REFERENCES produce_lot,
    quantity  integer  NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, line_no, lot_id),
    FOREIGN KEY (order_id, line_no) REFERENCES order_line ON DELETE CASCADE
);

-- Cash has no reference; transfers and POS payments must have one.
CREATE TABLE payment (
    payment_id  bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint        NOT NULL REFERENCES sales_order,
    amount      numeric(12,2) NOT NULL CHECK (amount > 0),
    method      varchar(10)   NOT NULL CHECK (method IN ('transfer', 'pos', 'cash')),
    reference   varchar(30)   UNIQUE,
    paid_at     timestamptz   NOT NULL DEFAULT now(),
    CHECK (method = 'cash' OR reference IS NOT NULL)
);


-- best_before is not stored. It is worked out from the commodity's shelf life.
CREATE VIEW lot_stock AS
SELECT l.lot_id,
       c.commodity_name,
       l.grade,
       cc.centre_name,
       l.qty_received,
       l.qty_remaining,
       l.received_at,
       (l.received_at::date + c.shelf_life_days) AS best_before
FROM produce_lot l
JOIN commodity c          ON c.commodity_id = l.commodity_id
JOIN collection_centre cc ON cc.centre_id = l.centre_id;
