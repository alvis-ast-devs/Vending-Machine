from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Product
from app.schemas import ProductCreate, ProductUpdate


def list_products(db: Session, include_inactive: bool = False) -> list[Product]:
    statement = select(Product).order_by(Product.slot_code)
    if not include_inactive:
        statement = statement.where(Product.is_active.is_(True))
    return list(db.scalars(statement).all())


def get_product(db: Session, product_id: int) -> Product | None:
    return db.get(Product, product_id)


def get_product_by_slot(db: Session, slot_code: str) -> Product | None:
    statement = select(Product).where(Product.slot_code == slot_code)
    return db.scalar(statement)


def create_product(db: Session, payload: ProductCreate) -> Product:
    product = Product(**payload.model_dump())
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


def update_product(
    db: Session,
    product: Product,
    payload: ProductUpdate,
) -> Product:
    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    for field, value in changes.items():
        setattr(product, field, value)
    db.commit()
    db.refresh(product)
    return product


def deactivate_product(db: Session, product: Product) -> Product:
    product.is_active = False
    db.commit()
    db.refresh(product)
    return product


def restock_product(db: Session, product: Product, full_stock: int) -> Product:
    product.stock = full_stock
    db.commit()
    db.refresh(product)
    return product


def set_product_image(
    db: Session,
    product: Product,
    *,
    stored_name: str,
    mime_type: str,
) -> Product:
    product.image_stored_name = stored_name
    product.image_mime_type = mime_type
    db.commit()
    db.refresh(product)
    return product


def clear_product_image(db: Session, product: Product) -> Product:
    product.image_stored_name = None
    product.image_mime_type = None
    db.commit()
    db.refresh(product)
    return product


def reduce_stock_after_drop(db: Session, product: Product) -> Product:
    product.stock -= 1
    db.commit()
    db.refresh(product)
    return product
