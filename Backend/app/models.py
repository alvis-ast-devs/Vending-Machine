from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Product(Base):
    __tablename__ = "products"
    __table_args__ = (
        CheckConstraint("price >= 0", name="ck_products_price_non_negative"),
        CheckConstraint("stock >= 0", name="ck_products_stock_non_negative"),
        CheckConstraint("length(slot_code) = 2", name="ck_products_slot_length"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    price: Mapped[int] = mapped_column(Integer, nullable=False)
    slot_code: Mapped[str] = mapped_column(String(2), unique=True, nullable=False)
    stock: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default=text("0"),
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default=text("true"),
    )
    image_stored_name: Mapped[str | None] = mapped_column(
        String(255),
        nullable=True,
    )
    image_mime_type: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
    )

    @property
    def image_url(self) -> str | None:
        if self.image_stored_name is None:
            return None
        return f"/media/{self.image_stored_name}"


class MediaAsset(Base):
    __tablename__ = "media_assets"
    __table_args__ = (
        CheckConstraint(
            "kind IN ('ad', 'tutorial', 'homescreen')",
            name="ck_media_assets_kind",
        ),
        CheckConstraint(
            "media_type IN ('image', 'video')",
            name="ck_media_assets_media_type",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    media_type: Mapped[str] = mapped_column(String(20), nullable=False)
    original_name: Mapped[str] = mapped_column(String(255), nullable=False)
    stored_name: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    mime_type: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )


class ThemeSettings(Base):
    __tablename__ = "theme_settings"
    __table_args__ = (
        CheckConstraint("id = 1", name="ck_theme_settings_singleton"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    background: Mapped[str] = mapped_column(String(7), nullable=False)
    surface: Mapped[str] = mapped_column(String(7), nullable=False)
    surface_soft: Mapped[str] = mapped_column(String(7), nullable=False)
    text_primary: Mapped[str] = mapped_column(String(7), nullable=False)
    text_muted: Mapped[str] = mapped_column(String(7), nullable=False)
    accent: Mapped[str] = mapped_column(String(7), nullable=False)
    warning: Mapped[str] = mapped_column(String(7), nullable=False)
    danger: Mapped[str] = mapped_column(String(7), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class PurchaseLog(Base):
    __tablename__ = "purchase_logs"
    __table_args__ = (
        CheckConstraint(
            "total_items >= 0",
            name="ck_purchase_logs_total_items_non_negative",
        ),
        CheckConstraint(
            "total_amount >= 0",
            name="ck_purchase_logs_total_amount_non_negative",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    transaction_id: Mapped[str | None] = mapped_column(
        String(100),
        unique=True,
        nullable=True,
    )
    total_items: Mapped[int] = mapped_column(Integer, nullable=False)
    total_amount: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )
    items: Mapped[list[PurchaseLogItem]] = relationship(
        back_populates="purchase_log",
        cascade="all, delete-orphan",
        order_by="PurchaseLogItem.id",
    )


class PurchaseLogItem(Base):
    __tablename__ = "purchase_log_items"
    __table_args__ = (
        CheckConstraint(
            "unit_price >= 0",
            name="ck_purchase_log_items_unit_price_non_negative",
        ),
        CheckConstraint(
            "quantity > 0",
            name="ck_purchase_log_items_quantity_positive",
        ),
        CheckConstraint(
            "subtotal >= 0",
            name="ck_purchase_log_items_subtotal_non_negative",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    purchase_log_id: Mapped[int] = mapped_column(
        ForeignKey("purchase_logs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    product_id: Mapped[int | None] = mapped_column(
        ForeignKey("products.id", ondelete="SET NULL"),
        nullable=True,
    )
    slot_code: Mapped[str] = mapped_column(String(2), nullable=False)
    product_name: Mapped[str] = mapped_column(String(120), nullable=False)
    unit_price: Mapped[int] = mapped_column(Integer, nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    subtotal: Mapped[int] = mapped_column(Integer, nullable=False)
    purchase_log: Mapped[PurchaseLog] = relationship(back_populates="items")
