from __future__ import annotations

from sqlalchemy import select, text

from app.config import settings
from app.database import Base, SessionLocal, engine
from app.models import Product


def physical_slot_codes() -> list[str]:
    codes = [f"{number:02d}" for number in range(1, 41)]
    codes.extend(f"{number:02d}" for number in range(41, 46))
    codes.extend(f"{number:02d}" for number in range(51, 56))
    assert len(codes) == 50
    return codes


def seed_products() -> int:
    Base.metadata.create_all(bind=engine)
    with engine.begin() as connection:
        connection.execute(
            text(
                "ALTER TABLE products ADD COLUMN IF NOT EXISTS "
                "image_stored_name VARCHAR(255)"
            )
        )
        connection.execute(
            text(
                "ALTER TABLE products ADD COLUMN IF NOT EXISTS "
                "image_mime_type VARCHAR(100)"
            )
        )
        if engine.dialect.name == "postgresql":
            connection.execute(
                text(
                    "ALTER TABLE media_assets DROP CONSTRAINT IF EXISTS "
                    "media_assets_kind_check"
                )
            )
            connection.execute(
                text(
                    "ALTER TABLE media_assets DROP CONSTRAINT IF EXISTS "
                    "ck_media_assets_kind"
                )
            )
            connection.execute(
                text(
                    "ALTER TABLE media_assets ADD CONSTRAINT "
                    "ck_media_assets_kind CHECK "
                    "(kind IN ('ad', 'tutorial', 'homescreen'))"
                )
            )
    created = 0

    with SessionLocal() as db:
        for index, slot_code in enumerate(physical_slot_codes()):
            existing = db.scalar(select(Product).where(Product.slot_code == slot_code))
            if existing is not None:
                continue

            is_large = index >= 40
            product_number = index + 1 if not is_large else index - 39
            product = Product(
                name=(
                    f"Produk Besar {product_number:02d}"
                    if is_large
                    else f"Snack {product_number:02d}"
                ),
                price=(
                    20_000 + ((index - 40) % 5) * 5_000
                    if is_large
                    else 8_000 + (index % 4) * 2_000
                ),
                slot_code=slot_code,
                stock=settings.full_stock,
                is_active=True,
            )
            db.add(product)
            created += 1

        db.commit()

    return created


if __name__ == "__main__":
    total_created = seed_products()
    print(f"Seed selesai: {total_created} produk baru dibuat.")
