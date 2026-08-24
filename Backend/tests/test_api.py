from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import PurchaseLog, PurchaseLogItem
from app.serial_bridge import parse_serial_event, serial_bridge

test_engine = create_engine(
    "sqlite+pysqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(
    bind=test_engine,
    autoflush=False,
    expire_on_commit=False,
)


def override_get_db():
    with TestingSessionLocal() as db:
        yield db


app.dependency_overrides[get_db] = override_get_db


@pytest.fixture(autouse=True)
def clean_database():
    Base.metadata.drop_all(bind=test_engine)
    Base.metadata.create_all(bind=test_engine)
    yield


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


def product_payload(slot_code: str = "11", stock: int = 2) -> dict:
    return {
        "name": "Keripik Kentang",
        "price": 12_000,
        "slot_code": slot_code,
        "stock": stock,
        "is_active": True,
    }


def test_product_crud_restock_and_soft_delete(client: TestClient):
    created = client.post("/api/products", json=product_payload())
    assert created.status_code == 201
    product_id = created.json()["id"]

    listed = client.get("/api/products")
    assert listed.status_code == 200
    assert len(listed.json()) == 1

    updated = client.put(
        f"/api/products/{product_id}",
        json={"name": "Keripik Pedas", "price": 15_000, "stock": 7},
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Keripik Pedas"
    assert updated.json()["price"] == 15_000
    assert updated.json()["stock"] == 7

    restocked = client.put(f"/api/products/{product_id}/restock")
    assert restocked.status_code == 200
    assert restocked.json()["stock"] == 10

    deactivated = client.put(f"/api/products/{product_id}/deactivate")
    assert deactivated.status_code == 200
    assert deactivated.json()["is_active"] is False
    assert client.get("/api/products").json() == []
    assert len(client.get("/api/products?include_inactive=true").json()) == 1


def test_duplicate_slot_returns_conflict(client: TestClient):
    assert client.post("/api/products", json=product_payload()).status_code == 201
    duplicate = client.post(
        "/api/products",
        json=product_payload(slot_code="11"),
    )
    assert duplicate.status_code == 409


def test_theme_defaults_update_validation_and_websocket(client: TestClient):
    defaults = client.get("/api/theme")
    assert defaults.status_code == 200
    assert defaults.json()["accent"] == "#19D37E"
    assert defaults.json()["background"] == "#101214"
    assert defaults.json()["updated_at"] is None

    palette = {
        "background": "#111827",
        "surface": "#1F2937",
        "surface_soft": "#374151",
        "text_primary": "#F9FAFB",
        "text_muted": "#D1D5DB",
        "accent": "#22C55E",
        "warning": "#F59E0B",
        "danger": "#EF4444",
    }
    with client.websocket_connect("/ws/machine") as websocket:
        updated = client.put("/api/theme", json=palette)
        event = websocket.receive_json()

    assert updated.status_code == 200
    assert updated.json()["accent"] == "#22C55E"
    assert updated.json()["updated_at"] is not None
    assert event["type"] == "THEME_UPDATED"
    assert event["data"]["surface_soft"] == "#374151"
    assert client.get("/api/theme").json()["background"] == "#111827"

    invalid = client.put("/api/theme", json={**palette, "accent": "green"})
    assert invalid.status_code == 422


def test_media_ads_and_single_tutorial_lifecycle(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
):
    monkeypatch.setattr("app.main.MEDIA_UPLOAD_DIR", tmp_path)

    empty_catalog = client.get("/api/media")
    assert empty_catalog.status_code == 200
    assert empty_catalog.json() == {
        "ads": [],
        "tutorial": None,
        "homescreen": None,
    }

    ad = client.post(
        "/api/media/ads",
        files={"file": ("promo.jpg", b"fake-jpeg", "image/jpeg")},
    )
    assert ad.status_code == 201
    assert ad.json()["media_type"] == "image"
    ad_file = tmp_path / Path(ad.json()["url"]).name
    assert ad_file.read_bytes() == b"fake-jpeg"

    first_tutorial = client.post(
        "/api/media/tutorial",
        files={"file": ("cara-pakai.mp4", b"first-video", "video/mp4")},
    )
    assert first_tutorial.status_code == 201
    first_tutorial_file = tmp_path / Path(first_tutorial.json()["url"]).name
    assert first_tutorial_file.is_file()

    replacement = client.post(
        "/api/media/tutorial",
        files={"file": ("cara-pakai-baru.mp4", b"second-video", "video/mp4")},
    )
    assert replacement.status_code == 201
    assert replacement.json()["id"] != first_tutorial.json()["id"]
    assert not first_tutorial_file.exists()

    first_homescreen = client.post(
        "/api/media/homescreen",
        files={"file": ("home.png", b"first-home", "image/png")},
    )
    assert first_homescreen.status_code == 201
    assert first_homescreen.json()["media_type"] == "image"
    first_homescreen_file = tmp_path / Path(first_homescreen.json()["url"]).name
    assert first_homescreen_file.read_bytes() == b"first-home"

    replacement_homescreen = client.post(
        "/api/media/homescreen",
        files={"file": ("home.mp4", b"second-home", "video/mp4")},
    )
    assert replacement_homescreen.status_code == 201
    assert replacement_homescreen.json()["media_type"] == "video"
    assert replacement_homescreen.json()["id"] != first_homescreen.json()["id"]
    assert not first_homescreen_file.exists()

    catalog = client.get("/api/media").json()
    assert [item["id"] for item in catalog["ads"]] == [ad.json()["id"]]
    assert catalog["tutorial"]["id"] == replacement.json()["id"]
    assert catalog["homescreen"]["id"] == replacement_homescreen.json()["id"]

    deleted = client.delete(f"/api/media/{ad.json()['id']}")
    assert deleted.status_code == 200
    assert not ad_file.exists()
    assert client.get("/api/media").json()["ads"] == []

    deleted_homescreen = client.delete(
        f"/api/media/{replacement_homescreen.json()['id']}"
    )
    assert deleted_homescreen.status_code == 200
    assert client.get("/api/media").json()["homescreen"] is None


def test_tutorial_rejects_image_upload(client: TestClient):
    response = client.post(
        "/api/media/tutorial",
        files={"file": ("tutorial.png", b"fake-image", "image/png")},
    )
    assert response.status_code == 415


def test_product_image_upload_replace_and_default(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
):
    monkeypatch.setattr("app.main.MEDIA_UPLOAD_DIR", tmp_path)
    created = client.post("/api/products", json=product_payload())
    product_id = created.json()["id"]
    assert created.json()["image_url"] is None

    uploaded = client.post(
        f"/api/products/{product_id}/image",
        files={"file": ("produk.png", b"first-image", "image/png")},
    )
    assert uploaded.status_code == 200
    first_file = tmp_path / Path(uploaded.json()["image_url"]).name
    assert first_file.read_bytes() == b"first-image"

    replaced = client.post(
        f"/api/products/{product_id}/image",
        files={"file": ("produk-baru.jpg", b"second-image", "image/jpeg")},
    )
    assert replaced.status_code == 200
    assert replaced.json()["image_url"].endswith(".jpg")
    assert not first_file.exists()

    removed = client.delete(f"/api/products/{product_id}/image")
    assert removed.status_code == 200
    assert removed.json()["image_url"] is None


def test_database_connection_error_returns_readable_503(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    def fail_to_list_products(*_args, **_kwargs):
        raise OperationalError("SELECT products", {}, Exception("database offline"))

    monkeypatch.setattr(
        "app.product_repository.list_products",
        fail_to_list_products,
    )

    response = client.get("/api/products")

    assert response.status_code == 503
    assert response.json() == {
        "detail": (
            "Koneksi database gagal. Periksa status PostgreSQL dan "
            "konfigurasi DATABASE_URL."
        )
    }


def test_websocket_ping_and_machine_events(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    assert client.post("/api/products", json=product_payload()).status_code == 201
    monkeypatch.setattr(
        serial_bridge,
        "drop_slot",
        lambda slot_code: f"SUCCESS_{slot_code}",
    )

    with client.websocket_connect("/ws/machine") as websocket:
        websocket.send_text("PING")
        assert websocket.receive_json()["type"] == "PONG"

        detected = client.post("/api/events/user-detected")
        assert detected.status_code == 200
        assert detected.json()["delivered_to"] == 1
        assert websocket.receive_json()["type"] == "USER_DETECTED"

        paid = client.post(
            "/api/events/payment-success",
            json={"transaction_id": "TRX-001", "slot_codes": ["11"]},
        )
        assert paid.status_code == 200
        payment_event = websocket.receive_json()
        assert payment_event["type"] == "PAYMENT_SUCCESS"
        assert payment_event["data"]["slot_codes"] == ["11"]


def test_payment_success_creates_purchase_snapshot(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.setattr(
        serial_bridge,
        "drop_slot",
        lambda slot_code: f"SUCCESS_{slot_code}",
    )
    first = client.post("/api/products", json=product_payload())
    second_payload = product_payload(slot_code="12")
    second_payload.update({"name": "Air Mineral", "price": 7_000})
    second = client.post("/api/products", json=second_payload)
    assert first.status_code == 201
    assert second.status_code == 201

    paid = client.post(
        "/api/events/payment-success",
        json={"transaction_id": "TRX-SNAPSHOT", "slot_codes": ["11", "11", "12"]},
    )
    assert paid.status_code == 200

    purchases = client.get("/api/purchases")
    assert purchases.status_code == 200
    assert len(purchases.json()) == 1
    purchase = purchases.json()[0]
    assert purchase["transaction_id"] == "TRX-SNAPSHOT"
    assert purchase["total_items"] == 3
    assert purchase["total_amount"] == 31_000
    assert purchase["created_at"]
    assert purchase["items"] == [
        {
            "id": purchase["items"][0]["id"],
            "product_id": first.json()["id"],
            "slot_code": "11",
            "product_name": "Keripik Kentang",
            "unit_price": 12_000,
            "quantity": 2,
            "subtotal": 24_000,
        },
        {
            "id": purchase["items"][1]["id"],
            "product_id": second.json()["id"],
            "slot_code": "12",
            "product_name": "Air Mineral",
            "unit_price": 7_000,
            "quantity": 1,
            "subtotal": 7_000,
        },
    ]
    products = {
        product["slot_code"]: product
        for product in client.get("/api/products").json()
    }
    assert products["11"]["stock"] == 0
    assert products["12"]["stock"] == 1

    client.put(
        f"/api/products/{first.json()['id']}",
        json={"name": "Nama Baru", "price": 99_000},
    )
    unchanged = client.get("/api/purchases").json()[0]
    assert unchanged["items"][0]["product_name"] == "Keripik Kentang"
    assert unchanged["items"][0]["unit_price"] == 12_000


def test_purchase_log_is_idempotent_and_keeps_only_latest_30(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    drops: list[str] = []

    def successful_drop(slot_code: str) -> str:
        drops.append(slot_code)
        return f"SUCCESS_{slot_code}"

    monkeypatch.setattr(serial_bridge, "drop_slot", successful_drop)
    assert (
        client.post("/api/products", json=product_payload(stock=40)).status_code
        == 201
    )

    for index in range(31):
        response = client.post(
            "/api/events/payment-success",
            json={"transaction_id": f"TRX-{index:03d}", "slot_codes": ["11"]},
        )
        assert response.status_code == 200

    duplicate = client.post(
        "/api/events/payment-success",
        json={"transaction_id": "TRX-030", "slot_codes": ["11"]},
    )
    assert duplicate.status_code == 200

    purchases = client.get("/api/purchases").json()
    assert len(purchases) == 30
    assert purchases[0]["transaction_id"] == "TRX-030"
    assert purchases[-1]["transaction_id"] == "TRX-001"
    assert "TRX-000" not in {purchase["transaction_id"] for purchase in purchases}
    assert len(drops) == 31
    assert client.get("/api/products/1").json()["stock"] == 9

    with TestingSessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(PurchaseLog)) == 30
        assert db.scalar(select(func.count()).select_from(PurchaseLogItem)) == 30


def test_payment_rejects_insufficient_stock_without_log_or_drop(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    created = client.post("/api/products", json=product_payload(stock=1))
    assert created.status_code == 201

    def unexpected_drop(_slot_code: str) -> str:
        pytest.fail("Hardware tidak boleh dijalankan jika stok tidak cukup")

    monkeypatch.setattr(serial_bridge, "drop_slot", unexpected_drop)
    response = client.post(
        "/api/events/payment-success",
        json={"transaction_id": "TRX-INSUFFICIENT", "slot_codes": ["11", "11"]},
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "Stok slot 11 tidak mencukupi"
    assert client.get("/api/products/1").json()["stock"] == 1
    assert client.get("/api/purchases").json() == []


def test_keypad_events_are_broadcast_to_flutter(client: TestClient):
    with client.websocket_connect("/ws/machine") as websocket:
        digit = client.post("/api/events/keypad/5")
        assert digit.status_code == 200
        assert websocket.receive_json() == {
            "type": "KEYPAD_DIGIT",
            "data": {"digit": "5"},
        }

        accepted = client.post("/api/events/keypad/ACCEPT")
        assert accepted.status_code == 200
        assert websocket.receive_json()["type"] == "KEYPAD_ACCEPT"

        declined = client.post("/api/events/keypad/DECLINED")
        assert declined.status_code == 200
        assert websocket.receive_json()["type"] == "KEYPAD_CANCEL"


def test_serial_event_lines_are_mapped_to_machine_events():
    assert parse_serial_event("EVENT_USER_DETECTED") == {
        "type": "USER_DETECTED",
        "data": {},
    }
    assert parse_serial_event("EVENT_KEY_7") == {
        "type": "KEYPAD_DIGIT",
        "data": {"digit": "7"},
    }
    assert parse_serial_event("EVENT_ACCEPT")["type"] == "KEYPAD_ACCEPT"
    assert parse_serial_event("EVENT_CANCEL")["type"] == "KEYPAD_CANCEL"
    assert parse_serial_event("READY") is None


def test_hardware_test_input_is_sent_to_esp32(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.setattr(
        serial_bridge,
        "send_test_input",
        lambda input_name: f"TEST_{input_name}",
    )

    response = client.post("/api/hardware/test-input/ACCEPT")
    assert response.status_code == 200
    assert response.json()["data"] == {"command": "TEST_ACCEPT"}


def test_drop_slot_waits_for_esp32_then_reduces_stock(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
):
    created = client.post("/api/products", json=product_payload(stock=2))
    assert created.status_code == 201

    monkeypatch.setattr(
        serial_bridge,
        "drop_slot",
        lambda slot_code: f"SUCCESS_{slot_code}",
    )
    dropped = client.post("/api/hardware/drop/11")

    assert dropped.status_code == 200
    assert dropped.json() == {
        "command": "DROP_SLOT_11",
        "response": "SUCCESS_11",
        "stock_remaining": 1,
    }


def test_drop_empty_slot_is_rejected(client: TestClient):
    assert (
        client.post("/api/products", json=product_payload(stock=0)).status_code == 201
    )
    response = client.post("/api/hardware/drop/11")
    assert response.status_code == 409


def test_mock_hardware_returns_success_without_opening_serial(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
):
    created = client.post("/api/products", json=product_payload(stock=2))
    assert created.status_code == 201

    monkeypatch.setattr(serial_bridge, "_hardware_enabled", False)

    def fail_if_serial_is_opened():
        pytest.fail("Mode mock tidak boleh membuka koneksi serial")

    monkeypatch.setattr(serial_bridge, "_ensure_connection", fail_if_serial_is_opened)

    dropped = client.post("/api/hardware/drop/11")

    assert dropped.status_code == 200
    assert dropped.json() == {
        "command": "DROP_SLOT_11",
        "response": "SUCCESS_11",
        "stock_remaining": 1,
    }
    console_output = capsys.readouterr().out
    assert "[MOCK HARDWARE] Mengirim: DROP_SLOT_11" in console_output
    assert "[MOCK HARDWARE] Menerima: SUCCESS_11" in console_output
