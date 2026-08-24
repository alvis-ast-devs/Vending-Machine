from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

SlotCode = Annotated[str, Field(pattern=r"^\d{2}$")]
HexColor = Annotated[str, Field(pattern=r"^#[0-9A-Fa-f]{6}$")]


class ThemeSettingsBase(BaseModel):
    background: HexColor = "#101214"
    surface: HexColor = "#1A1D21"
    surface_soft: HexColor = "#24282E"
    text_primary: HexColor = "#F8FAFC"
    text_muted: HexColor = "#9CA3AF"
    accent: HexColor = "#19D37E"
    warning: HexColor = "#FFC857"
    danger: HexColor = "#FF5D5D"

    @field_validator(
        "background",
        "surface",
        "surface_soft",
        "text_primary",
        "text_muted",
        "accent",
        "warning",
        "danger",
    )
    @classmethod
    def normalize_hex_color(cls, value: str) -> str:
        return value.upper()


class ThemeSettingsUpdate(ThemeSettingsBase):
    pass


class ThemeSettingsResponse(ThemeSettingsBase):
    model_config = ConfigDict(from_attributes=True)

    updated_at: datetime | None = None


class ProductBase(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    price: int = Field(ge=0)
    slot_code: SlotCode
    stock: int = Field(default=0, ge=0)
    is_active: bool = True

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("name tidak boleh kosong")
        return cleaned


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    price: int | None = Field(default=None, ge=0)
    slot_code: SlotCode | None = None
    stock: int | None = Field(default=None, ge=0)
    is_active: bool | None = None

    @field_validator("name")
    @classmethod
    def clean_optional_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("name tidak boleh kosong")
        return cleaned


class ProductResponse(ProductBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    image_url: str | None = None


class EventResponse(BaseModel):
    type: str
    delivered_to: int


class PaymentSuccessRequest(BaseModel):
    transaction_id: str | None = Field(default=None, max_length=100)
    slot_codes: list[SlotCode] = Field(min_length=1)


class PurchaseLogItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    product_id: int | None
    slot_code: SlotCode
    product_name: str
    unit_price: int
    quantity: int
    subtotal: int


class PurchaseLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    transaction_id: str | None
    total_items: int
    total_amount: int
    created_at: datetime
    items: list[PurchaseLogItemResponse]


class DropSlotResponse(BaseModel):
    command: str
    response: str
    stock_remaining: int


class MessageResponse(BaseModel):
    message: str
    data: dict[str, Any] | None = None


class MediaAssetResponse(BaseModel):
    id: int
    kind: Literal["ad", "tutorial", "homescreen"]
    media_type: Literal["image", "video"]
    original_name: str
    mime_type: str
    url: str
    created_at: datetime


class MediaCatalogResponse(BaseModel):
    ads: list[MediaAssetResponse]
    tutorial: MediaAssetResponse | None = None
    homescreen: MediaAssetResponse | None = None
