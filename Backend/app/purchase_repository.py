from __future__ import annotations

from collections import Counter

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import Product, PurchaseLog, PurchaseLogItem
from app.schemas import PaymentSuccessRequest

MAX_PURCHASE_LOGS = 30


class PurchaseProductUnavailableError(ValueError):
    def __init__(self, slot_code: str) -> None:
        self.slot_code = slot_code
        super().__init__(slot_code)


class PurchaseStockInsufficientError(ValueError):
    def __init__(self, slot_code: str) -> None:
        self.slot_code = slot_code
        super().__init__(slot_code)


def list_purchase_logs(db: Session) -> list[PurchaseLog]:
    statement = (
        select(PurchaseLog)
        .options(selectinload(PurchaseLog.items))
        .order_by(PurchaseLog.created_at.desc(), PurchaseLog.id.desc())
        .limit(MAX_PURCHASE_LOGS)
    )
    return list(db.scalars(statement).all())


def get_purchase_log_by_transaction_id(
    db: Session,
    transaction_id: str,
) -> PurchaseLog | None:
    return db.scalar(
        select(PurchaseLog)
        .options(selectinload(PurchaseLog.items))
        .where(PurchaseLog.transaction_id == transaction_id)
    )


def prepare_purchase(
    db: Session,
    slot_codes: list[str],
) -> dict[str, Product]:
    quantities = Counter(slot_codes)
    statement = (
        select(Product)
        .where(Product.slot_code.in_(quantities))
        .with_for_update()
    )
    products = {
        product.slot_code: product for product in db.scalars(statement).all()
    }

    for slot_code, quantity in quantities.items():
        product = products.get(slot_code)
        if product is None or not product.is_active:
            raise PurchaseProductUnavailableError(slot_code)
        if product.stock < quantity:
            raise PurchaseStockInsufficientError(slot_code)

    return products


def create_purchase_log(
    db: Session,
    payload: PaymentSuccessRequest,
    *,
    products_by_slot: dict[str, Product] | None = None,
    reduce_stock: bool = False,
) -> PurchaseLog:
    if payload.transaction_id is not None:
        existing = db.scalar(
            select(PurchaseLog)
            .options(selectinload(PurchaseLog.items))
            .where(PurchaseLog.transaction_id == payload.transaction_id)
        )
        if existing is not None:
            return existing

    quantities = Counter(payload.slot_codes)
    products = products_by_slot
    if products is None:
        products = {
            product.slot_code: product
            for product in db.scalars(
                select(Product).where(Product.slot_code.in_(quantities))
            ).all()
        }

    purchase = PurchaseLog(
        transaction_id=payload.transaction_id,
        total_items=sum(quantities.values()),
        total_amount=0,
    )
    for slot_code, quantity in quantities.items():
        product = products.get(slot_code)
        unit_price = product.price if product is not None else 0
        subtotal = unit_price * quantity
        if reduce_stock and product is not None:
            product.stock -= quantity
        purchase.items.append(
            PurchaseLogItem(
                product_id=product.id if product is not None else None,
                slot_code=slot_code,
                product_name=(
                    product.name if product is not None else f"Produk slot {slot_code}"
                ),
                unit_price=unit_price,
                quantity=quantity,
                subtotal=subtotal,
            )
        )
        purchase.total_amount += subtotal

    db.add(purchase)
    db.flush()

    old_logs = list(
        db.scalars(
            select(PurchaseLog)
            .order_by(PurchaseLog.created_at.desc(), PurchaseLog.id.desc())
            .offset(MAX_PURCHASE_LOGS)
        ).all()
    )
    for old_log in old_logs:
        db.delete(old_log)

    db.commit()
    db.refresh(purchase)
    return purchase
