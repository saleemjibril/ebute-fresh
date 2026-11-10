# ER diagram

The diagram is written in Mermaid so it renders on GitHub. A PNG copy is in
`er-diagram.png`. Only keys and the columns that matter for relationships are shown;
the full column list is in `schema.sql`.

```mermaid
erDiagram
    STATE ||--o{ COLLECTION_CENTRE : "has"
    COLLECTION_CENTRE ||--o{ STAFF : "employs"
    COLLECTION_CENTRE ||--o{ FARMER : "home centre of"
    COLLECTION_CENTRE ||--o{ PRODUCE_LOT : "receives"
    FARMER ||--o{ PRODUCE_LOT : "delivers"
    STAFF ||--o{ PRODUCE_LOT : "records"
    COMMODITY ||--o{ PRODUCE_LOT : "is of"
    COMMODITY ||--o{ COMMODITY_PRICE : "priced by"
    FARMER ||--o{ FARMER_PAYOUT : "is paid by"
    STAFF ||--o{ FARMER_PAYOUT : "authorises"
    FARMER_PAYOUT |o--o{ PRODUCE_LOT : "settles"
    CUSTOMER ||--o{ SALES_ORDER : "places"
    STAFF ||--o{ SALES_ORDER : "takes"
    SALES_ORDER ||--|{ ORDER_LINE : "contains"
    COMMODITY ||--o{ ORDER_LINE : "ordered as"
    ORDER_LINE ||--o{ ALLOCATION : "filled by"
    PRODUCE_LOT ||--o{ ALLOCATION : "supplies"
    SALES_ORDER ||--o{ PAYMENT : "paid by"

    STATE {
        char state_code PK
        varchar state_name UK
    }
    COLLECTION_CENTRE {
        smallint centre_id PK
        varchar centre_name UK
        char state_code FK
    }
    STAFF {
        int staff_id PK
        varchar role
        smallint centre_id FK "intake officers only"
    }
    FARMER {
        int farmer_id PK
        varchar phone UK
        smallint home_centre_id FK
    }
    COMMODITY {
        smallint commodity_id PK
        varchar commodity_name UK
        varchar unit
        smallint shelf_life_days
    }
    COMMODITY_PRICE {
        smallint commodity_id PK,FK
        char grade PK
        date effective_from PK
        numeric selling_price
    }
    FARMER_PAYOUT {
        bigint payout_id PK
        int farmer_id FK
        int paid_by FK
        varchar bank_ref UK
    }
    PRODUCE_LOT {
        bigint lot_id PK
        int farmer_id FK
        smallint centre_id FK
        smallint commodity_id FK
        int received_by FK
        bigint payout_id FK "null until paid"
        char grade
        int qty_received
        int qty_remaining
    }
    CUSTOMER {
        int customer_id PK
        varchar customer_type
        varchar phone UK
    }
    SALES_ORDER {
        bigint order_id PK
        int customer_id FK
        int taken_by FK
        varchar status
    }
    ORDER_LINE {
        bigint order_id PK,FK
        smallint line_no PK
        smallint commodity_id FK
        char grade
        int quantity
        numeric unit_price
    }
    ALLOCATION {
        bigint order_id PK,FK
        smallint line_no PK,FK
        bigint lot_id PK,FK
        int quantity
    }
    PAYMENT {
        bigint payment_id PK
        bigint order_id FK
        varchar method
        varchar reference UK
    }
```

## Notes on the relationships

- **Order line to lot is many-to-many.** One order line for 40 crates of grade A tomatoes
  might be filled from three farmers' lots, and one large lot can be split across many
  orders. `allocation` sits between them and records how much of each lot went to each
  line. Following order line to allocation to lot to farmer is how an order is traced
  back to the farms it came from.
- **Payout to lot is optional on the lot side.** A lot has no payout until finance pays
  the farmer, so `produce_lot.payout_id` is nullable. A composite foreign key on
  `(payout_id, farmer_id)` stops a lot being settled through another farmer's payout.
- **Staff to lot.** The receiving officer must be an intake officer at the same centre as
  the lot. This is enforced with a composite foreign key on `(received_by, centre_id)`
  rather than a trigger.
- **Sales order to order line is one-to-many with at least one line** (`||--|{`). The
  database cannot force "at least one" with a plain constraint, so the application
  inserts the order and its lines in one transaction (covered in Portfolio 3).
- **Commodity price** is a weak entity: it only exists for a commodity, and its key
  includes the commodity, grade and the date the price took effect.
