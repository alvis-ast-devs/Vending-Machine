from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import MediaAsset


def list_assets(db: Session, kind: str | None = None) -> list[MediaAsset]:
    statement = select(MediaAsset).order_by(MediaAsset.id)
    if kind is not None:
        statement = statement.where(MediaAsset.kind == kind)
    return list(db.scalars(statement).all())


def get_asset(db: Session, asset_id: int) -> MediaAsset | None:
    return db.get(MediaAsset, asset_id)


def create_asset(
    db: Session,
    *,
    kind: str,
    media_type: str,
    original_name: str,
    stored_name: str,
    mime_type: str,
) -> MediaAsset:
    asset = MediaAsset(
        kind=kind,
        media_type=media_type,
        original_name=original_name,
        stored_name=stored_name,
        mime_type=mime_type,
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)
    return asset


def replace_single_asset(
    db: Session,
    *,
    kind: str,
    media_type: str,
    original_name: str,
    stored_name: str,
    mime_type: str,
) -> tuple[MediaAsset, list[MediaAsset]]:
    previous_assets = list_assets(db, kind)
    for previous in previous_assets:
        db.delete(previous)

    asset = MediaAsset(
        kind=kind,
        media_type=media_type,
        original_name=original_name,
        stored_name=stored_name,
        mime_type=mime_type,
    )
    db.add(asset)
    db.commit()
    db.refresh(asset)
    return asset, previous_assets


def delete_asset(db: Session, asset: MediaAsset) -> None:
    db.delete(asset)
    db.commit()
