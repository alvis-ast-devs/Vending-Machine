CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    price INTEGER NOT NULL CHECK (price >= 0),
    slot_code VARCHAR(2) NOT NULL UNIQUE
        CHECK (slot_code ~ '^[0-9]{2}$'),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    image_stored_name VARCHAR(255),
    image_mime_type VARCHAR(100)
);

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS image_stored_name VARCHAR(255);

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS image_mime_type VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_products_active_slot
    ON products (is_active, slot_code);

CREATE TABLE IF NOT EXISTS media_assets (
    id SERIAL PRIMARY KEY,
    kind VARCHAR(20) NOT NULL,
    media_type VARCHAR(20) NOT NULL CHECK (media_type IN ('image', 'video')),
    original_name VARCHAR(255) NOT NULL,
    stored_name VARCHAR(255) NOT NULL UNIQUE,
    mime_type VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE media_assets
    DROP CONSTRAINT IF EXISTS media_assets_kind_check;

ALTER TABLE media_assets
    DROP CONSTRAINT IF EXISTS ck_media_assets_kind;

ALTER TABLE media_assets
    ADD CONSTRAINT ck_media_assets_kind
    CHECK (kind IN ('ad', 'tutorial', 'homescreen'));

CREATE INDEX IF NOT EXISTS idx_media_assets_kind
    ON media_assets (kind);

CREATE TABLE IF NOT EXISTS theme_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    background VARCHAR(7) NOT NULL,
    surface VARCHAR(7) NOT NULL,
    surface_soft VARCHAR(7) NOT NULL,
    text_primary VARCHAR(7) NOT NULL,
    text_muted VARCHAR(7) NOT NULL,
    accent VARCHAR(7) NOT NULL,
    warning VARCHAR(7) NOT NULL,
    danger VARCHAR(7) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_logs (
    id SERIAL PRIMARY KEY,
    transaction_id VARCHAR(100) UNIQUE,
    total_items INTEGER NOT NULL CHECK (total_items >= 0),
    total_amount INTEGER NOT NULL CHECK (total_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_purchase_logs_created_at
    ON purchase_logs (created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS purchase_log_items (
    id SERIAL PRIMARY KEY,
    purchase_log_id INTEGER NOT NULL
        REFERENCES purchase_logs (id) ON DELETE CASCADE,
    product_id INTEGER
        REFERENCES products (id) ON DELETE SET NULL,
    slot_code VARCHAR(2) NOT NULL CHECK (slot_code ~ '^[0-9]{2}$'),
    product_name VARCHAR(120) NOT NULL,
    unit_price INTEGER NOT NULL CHECK (unit_price >= 0),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    subtotal INTEGER NOT NULL CHECK (subtotal >= 0)
);

CREATE INDEX IF NOT EXISTS idx_purchase_log_items_purchase_log
    ON purchase_log_items (purchase_log_id);
