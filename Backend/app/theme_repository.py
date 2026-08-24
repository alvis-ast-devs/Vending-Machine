from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models import ThemeSettings
from app.schemas import ThemeSettingsBase, ThemeSettingsUpdate


def ensure_theme_table(db: Session) -> None:
    """Create the small settings table for existing installations without migrations."""
    ThemeSettings.__table__.create(bind=db.get_bind(), checkfirst=True)


def get_theme(db: Session) -> ThemeSettings | None:
    ensure_theme_table(db)
    return db.get(ThemeSettings, 1)


def get_theme_or_default(db: Session) -> ThemeSettings | ThemeSettingsBase:
    return get_theme(db) or ThemeSettingsBase()


def update_theme(db: Session, payload: ThemeSettingsUpdate) -> ThemeSettings:
    ensure_theme_table(db)
    theme = db.get(ThemeSettings, 1)
    values = payload.model_dump()
    if theme is None:
        theme = ThemeSettings(id=1, **values)
        db.add(theme)
    else:
        for field, value in values.items():
            setattr(theme, field, value)
        theme.updated_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(theme)
    return theme
