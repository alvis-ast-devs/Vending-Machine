from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path as FilePath
from typing import Annotated
from uuid import uuid4

from fastapi import (
    Depends,
    FastAPI,
    File,
    HTTPException,
    Path,
    Request,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from app import (
    media_repository,
    product_repository,
    purchase_repository,
    theme_repository,
)
from app.config import settings
from app.database import get_db
from app.schemas import (
    DropSlotResponse,
    EventResponse,
    MediaAssetResponse,
    MediaCatalogResponse,
    MessageResponse,
    PaymentSuccessRequest,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
    PurchaseLogResponse,
    ThemeSettingsResponse,
    ThemeSettingsUpdate,
)
from app.serial_bridge import SerialBridgeError, serial_bridge
from app.websocket_manager import websocket_manager

DbSession = Annotated[Session, Depends(get_db)]
PhysicalSlotCode = Annotated[str, Path(pattern=r"^\d{2}$")]
logger = logging.getLogger("uvicorn.error")
MEDIA_UPLOAD_DIR = FilePath(settings.media_upload_dir).resolve()
MEDIA_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
payment_processing_lock = asyncio.Lock()

IMAGE_TYPES = {
    "image/jpeg": {".jpg", ".jpeg"},
    "image/png": {".png"},
    "image/webp": {".webp"},
    "image/gif": {".gif"},
    "image/bmp": {".bmp"},
    "image/x-ms-bmp": {".bmp"},
}
VIDEO_TYPES = {
    "video/mp4": {".mp4"},
    "video/webm": {".webm"},
    "video/quicktime": {".mov"},
    "video/x-matroska": {".mkv"},
}


@asynccontextmanager
async def lifespan(_: FastAPI):
    event_loop = asyncio.get_running_loop()

    def forward_serial_event(event: dict) -> None:
        try:
            asyncio.run_coroutine_threadsafe(
                websocket_manager.broadcast(event),
                event_loop,
            )
        except RuntimeError:
            logger.warning("Event serial diabaikan karena backend sedang berhenti")

    serial_bridge.start_event_listener(forward_serial_event)
    try:
        yield
    finally:
        serial_bridge.close()


app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.mount("/media", StaticFiles(directory=MEDIA_UPLOAD_DIR), name="media")


def media_response(asset) -> MediaAssetResponse:
    return MediaAssetResponse(
        id=asset.id,
        kind=asset.kind,
        media_type=asset.media_type,
        original_name=asset.original_name,
        mime_type=asset.mime_type,
        url=f"/media/{asset.stored_name}",
        created_at=asset.created_at,
    )


def remove_media_file(stored_name: str) -> None:
    file_path = (MEDIA_UPLOAD_DIR / stored_name).resolve()
    if file_path.parent == MEDIA_UPLOAD_DIR and file_path.is_file():
        file_path.unlink(missing_ok=True)


async def save_media_upload(
    upload: UploadFile,
    *,
    allowed_types: dict[str, set[str]],
) -> tuple[str, str, str]:
    original_name = FilePath(upload.filename or "media").name[:255]
    extension = FilePath(original_name).suffix.lower()
    mime_type = (upload.content_type or "").lower()
    allowed_extensions = allowed_types.get(mime_type)
    if allowed_extensions is None or extension not in allowed_extensions:
        allowed = "foto PNG/JPG/WebP/GIF/BMP atau video MP4/WebM/MOV/MKV"
        if allowed_types == VIDEO_TYPES:
            allowed = "video MP4/WebM/MOV/MKV"
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Format tidak didukung. Gunakan {allowed}.",
        )

    media_type = "image" if mime_type in IMAGE_TYPES else "video"
    max_bytes = (
        (
            settings.max_image_upload_mb
            if media_type == "image"
            else settings.max_video_upload_mb
        )
        * 1024
        * 1024
    )
    stored_name = f"{uuid4().hex}{extension}"
    destination = MEDIA_UPLOAD_DIR / stored_name
    written = 0

    try:
        with destination.open("wb") as output:
            while chunk := await upload.read(1024 * 1024):
                written += len(chunk)
                if written > max_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=(
                            f"File terlalu besar. Maksimum "
                            f"{max_bytes // (1024 * 1024)} MB."
                        ),
                    )
                output.write(chunk)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    finally:
        await upload.close()

    return original_name, stored_name, mime_type


@app.exception_handler(OperationalError)
async def database_connection_error(
    _: Request,
    __: OperationalError,
) -> JSONResponse:
    logger.error(
        "PostgreSQL tidak dapat diakses. Periksa DATABASE_URL, password, dan "
        "status server database."
    )
    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content={
            "detail": (
                "Koneksi database gagal. Periksa status PostgreSQL dan "
                "konfigurasi DATABASE_URL."
            )
        },
    )


def require_product(db: Session, product_id: int):
    product = product_repository.get_product(db, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    return product


def raise_slot_conflict(db: Session, error: IntegrityError) -> None:
    db.rollback()
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="Kode slot sudah digunakan oleh produk lain",
    ) from error


@app.get("/health", response_model=MessageResponse)
def health_check(db: DbSession) -> MessageResponse:
    db.execute(text("SELECT 1"))
    return MessageResponse(
        message="ok",
        data={
            "websocket_clients": websocket_manager.connection_count,
            "hardware_mode": ("serial" if serial_bridge.hardware_enabled else "mock"),
            "serial_port": settings.serial_port,
        },
    )


@app.get("/api/products", response_model=list[ProductResponse])
def get_products(
    db: DbSession,
    include_inactive: bool = False,
):
    return product_repository.list_products(db, include_inactive)


@app.get("/api/products/{product_id}", response_model=ProductResponse)
def get_product(product_id: int, db: DbSession):
    return require_product(db, product_id)


@app.get("/api/theme", response_model=ThemeSettingsResponse)
def get_theme(db: DbSession):
    return theme_repository.get_theme_or_default(db)


@app.put("/api/theme", response_model=ThemeSettingsResponse)
async def update_theme(payload: ThemeSettingsUpdate, db: DbSession):
    theme = theme_repository.update_theme(db, payload)
    response = ThemeSettingsResponse.model_validate(theme)
    await websocket_manager.broadcast(
        {
            "type": "THEME_UPDATED",
            "data": response.model_dump(mode="json"),
        }
    )
    return response


@app.get("/api/media", response_model=MediaCatalogResponse)
def get_media_catalog(db: DbSession) -> MediaCatalogResponse:
    assets = media_repository.list_assets(db)
    ads = [media_response(asset) for asset in assets if asset.kind == "ad"]
    tutorial = next(
        (
            media_response(asset)
            for asset in reversed(assets)
            if asset.kind == "tutorial"
        ),
        None,
    )
    homescreen = next(
        (
            media_response(asset)
            for asset in reversed(assets)
            if asset.kind == "homescreen"
        ),
        None,
    )
    return MediaCatalogResponse(
        ads=ads,
        tutorial=tutorial,
        homescreen=homescreen,
    )


@app.get("/api/purchases", response_model=list[PurchaseLogResponse])
def get_purchase_logs(db: DbSession):
    return purchase_repository.list_purchase_logs(db)


@app.post(
    "/api/products/{product_id}/image",
    response_model=ProductResponse,
)
async def upload_product_image(
    product_id: int,
    db: DbSession,
    file: Annotated[UploadFile, File()],
):
    product = require_product(db, product_id)
    previous_stored_name = product.image_stored_name
    _, stored_name, mime_type = await save_media_upload(
        file,
        allowed_types=IMAGE_TYPES,
    )
    try:
        updated_product = product_repository.set_product_image(
            db,
            product,
            stored_name=stored_name,
            mime_type=mime_type,
        )
    except Exception:
        remove_media_file(stored_name)
        raise

    if previous_stored_name is not None:
        remove_media_file(previous_stored_name)
    return updated_product


@app.delete(
    "/api/products/{product_id}/image",
    response_model=ProductResponse,
)
def delete_product_image(product_id: int, db: DbSession):
    product = require_product(db, product_id)
    previous_stored_name = product.image_stored_name
    updated_product = product_repository.clear_product_image(db, product)
    if previous_stored_name is not None:
        remove_media_file(previous_stored_name)
    return updated_product


@app.post(
    "/api/media/ads",
    response_model=MediaAssetResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_ad_media(
    db: DbSession,
    file: Annotated[UploadFile, File()],
) -> MediaAssetResponse:
    original_name, stored_name, mime_type = await save_media_upload(
        file,
        allowed_types={**IMAGE_TYPES, **VIDEO_TYPES},
    )
    try:
        asset = media_repository.create_asset(
            db,
            kind="ad",
            media_type="image" if mime_type in IMAGE_TYPES else "video",
            original_name=original_name,
            stored_name=stored_name,
            mime_type=mime_type,
        )
    except Exception:
        remove_media_file(stored_name)
        raise
    return media_response(asset)


@app.post(
    "/api/media/tutorial",
    response_model=MediaAssetResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_tutorial_media(
    db: DbSession,
    file: Annotated[UploadFile, File()],
) -> MediaAssetResponse:
    original_name, stored_name, mime_type = await save_media_upload(
        file,
        allowed_types=VIDEO_TYPES,
    )
    try:
        asset, previous_assets = media_repository.replace_single_asset(
            db,
            kind="tutorial",
            media_type="video",
            original_name=original_name,
            stored_name=stored_name,
            mime_type=mime_type,
        )
    except Exception:
        remove_media_file(stored_name)
        raise

    for previous in previous_assets:
        remove_media_file(previous.stored_name)
    return media_response(asset)


@app.post(
    "/api/media/homescreen",
    response_model=MediaAssetResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_homescreen_media(
    db: DbSession,
    file: Annotated[UploadFile, File()],
) -> MediaAssetResponse:
    original_name, stored_name, mime_type = await save_media_upload(
        file,
        allowed_types={**IMAGE_TYPES, **VIDEO_TYPES},
    )
    try:
        asset, previous_assets = media_repository.replace_single_asset(
            db,
            kind="homescreen",
            media_type="image" if mime_type in IMAGE_TYPES else "video",
            original_name=original_name,
            stored_name=stored_name,
            mime_type=mime_type,
        )
    except Exception:
        remove_media_file(stored_name)
        raise

    for previous in previous_assets:
        remove_media_file(previous.stored_name)
    return media_response(asset)


@app.delete("/api/media/{asset_id}", response_model=MessageResponse)
def delete_media(asset_id: int, db: DbSession) -> MessageResponse:
    asset = media_repository.get_asset(db, asset_id)
    if asset is None:
        raise HTTPException(status_code=404, detail="Media tidak ditemukan")

    stored_name = asset.stored_name
    media_repository.delete_asset(db, asset)
    remove_media_file(stored_name)
    return MessageResponse(message="Media berhasil dihapus")


@app.post(
    "/api/products",
    response_model=ProductResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_product(payload: ProductCreate, db: DbSession):
    try:
        return product_repository.create_product(db, payload)
    except IntegrityError as error:
        raise_slot_conflict(db, error)


@app.put("/api/products/{product_id}", response_model=ProductResponse)
def update_product(
    product_id: int,
    payload: ProductUpdate,
    db: DbSession,
):
    product = require_product(db, product_id)
    try:
        return product_repository.update_product(db, product, payload)
    except IntegrityError as error:
        raise_slot_conflict(db, error)


@app.put("/api/products/{product_id}/deactivate", response_model=ProductResponse)
def deactivate_product(product_id: int, db: DbSession):
    product = require_product(db, product_id)
    return product_repository.deactivate_product(db, product)


@app.put("/api/products/{product_id}/restock", response_model=ProductResponse)
def restock_product(product_id: int, db: DbSession):
    product = require_product(db, product_id)
    return product_repository.restock_product(db, product, settings.full_stock)


@app.post("/api/events/user-detected", response_model=EventResponse)
async def send_user_detected():
    event_type = "USER_DETECTED"
    delivered = await websocket_manager.broadcast({"type": event_type, "data": {}})
    return EventResponse(type=event_type, delivered_to=delivered)


@app.post("/api/events/keypad/{key}", response_model=EventResponse)
async def send_keypad_event(
    key: Annotated[str, Path(pattern=r"^(?:[0-9]|ACCEPT|CANCEL|DECLINED)$")],
):
    normalized = key.upper()
    if normalized.isdigit():
        event_type = "KEYPAD_DIGIT"
        data = {"digit": normalized}
    elif normalized == "ACCEPT":
        event_type = "KEYPAD_ACCEPT"
        data = {}
    else:
        event_type = "KEYPAD_CANCEL"
        data = {}

    delivered = await websocket_manager.broadcast({"type": event_type, "data": data})
    return EventResponse(type=event_type, delivered_to=delivered)


@app.post("/api/events/payment-success", response_model=EventResponse)
async def send_payment_success(payload: PaymentSuccessRequest, db: DbSession):
    transaction_id = payload.transaction_id or f"TRX-{uuid4().hex[:12].upper()}"
    confirmed_payload = payload.model_copy(
        update={"transaction_id": transaction_id},
    )

    async with payment_processing_lock:
        existing = purchase_repository.get_purchase_log_by_transaction_id(
            db,
            transaction_id,
        )
        if existing is not None:
            confirmed_payload = confirmed_payload.model_copy(
                update={
                    "slot_codes": [
                        item.slot_code
                        for item in existing.items
                        for _ in range(item.quantity)
                    ]
                }
            )
        else:
            try:
                products = purchase_repository.prepare_purchase(
                    db,
                    confirmed_payload.slot_codes,
                )
            except purchase_repository.PurchaseProductUnavailableError as error:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Produk slot {error.slot_code} tidak tersedia",
                ) from error
            except purchase_repository.PurchaseStockInsufficientError as error:
                db.rollback()
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"Stok slot {error.slot_code} tidak mencukupi",
                ) from error

            try:
                for slot_code in confirmed_payload.slot_codes:
                    await asyncio.to_thread(serial_bridge.drop_slot, slot_code)
            except SerialBridgeError as error:
                db.rollback()
                raise HTTPException(status_code=503, detail=str(error)) from error

            purchase_repository.create_purchase_log(
                db,
                confirmed_payload,
                products_by_slot=products,
                reduce_stock=True,
            )

    event_type = "PAYMENT_SUCCESS"
    delivered = await websocket_manager.broadcast(
        {
            "type": event_type,
            "data": {
                "transaction_id": confirmed_payload.transaction_id,
                "slot_codes": confirmed_payload.slot_codes,
            },
        }
    )
    return EventResponse(type=event_type, delivered_to=delivered)


@app.post(
    "/api/hardware/drop/{slot_code}",
    response_model=DropSlotResponse,
)
async def drop_product(
    slot_code: PhysicalSlotCode,
    db: DbSession,
):
    product = product_repository.get_product_by_slot(db, slot_code)
    if product is None or not product.is_active:
        raise HTTPException(status_code=404, detail="Slot aktif tidak ditemukan")
    if product.stock <= 0:
        raise HTTPException(status_code=409, detail="Stok slot kosong")

    try:
        response = await asyncio.to_thread(serial_bridge.drop_slot, slot_code)
    except SerialBridgeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error

    product_repository.reduce_stock_after_drop(db, product)
    return DropSlotResponse(
        command=f"DROP_SLOT_{slot_code}",
        response=response,
        stock_remaining=product.stock,
    )


@app.post("/api/hardware/test-input/{input_name}", response_model=MessageResponse)
async def send_hardware_test_input(
    input_name: Annotated[
        str,
        Path(pattern=r"^(?:DETECT|ACCEPT|CANCEL|DECLINED|KEY_[0-9])$"),
    ],
):
    try:
        command = await asyncio.to_thread(serial_bridge.send_test_input, input_name)
    except SerialBridgeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    return MessageResponse(
        message="Perintah tes dikirim ke ESP32",
        data={"command": command},
    )


@app.websocket("/ws/machine")
async def machine_websocket(websocket: WebSocket):
    await websocket_manager.connect(websocket)
    try:
        while True:
            message = (await websocket.receive_text()).strip().upper()
            if message == "PING":
                await websocket.send_json({"type": "PONG", "data": {}})
            else:
                await websocket.send_json(
                    {
                        "type": "ERROR",
                        "data": {"message": "Pesan WebSocket tidak dikenal"},
                    }
                )
    except WebSocketDisconnect:
        websocket_manager.disconnect(websocket)
