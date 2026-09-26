"""SQLAlchemy engine, models, and session helpers.

Uses DATABASE_URL when set (Neon / Render Postgres). Otherwise SQLite under
backend/data/app.db so local demos work without cloud credentials.
"""

from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Generator

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    create_engine,
    event,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship, sessionmaker

APP_DIR = Path(__file__).resolve().parent
DATA_DIR = APP_DIR / "data"
DEFAULT_SQLITE = f"sqlite:///{(DATA_DIR / 'app.db').as_posix()}"


def _database_url() -> str:
    raw = (os.environ.get("DATABASE_URL") or "").strip()
    if not raw:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        return DEFAULT_SQLITE
    # Render / Neon sometimes hand out postgres:// — SQLAlchemy wants postgresql://
    if raw.startswith("postgres://"):
        raw = "postgresql://" + raw[len("postgres://") :]
    return raw


DATABASE_URL = _database_url()
_is_sqlite = DATABASE_URL.startswith("sqlite")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if _is_sqlite else {},
    pool_pre_ping=not _is_sqlite,
)

if _is_sqlite:

    @event.listens_for(engine, "connect")
    def _sqlite_fk(dbapi_connection, connection_record) -> None:  # type: ignore[no-untyped-def]
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    # Nullable so legacy anonymous device accounts keep working.
    email: Mapped[str | None] = mapped_column(String(320), unique=True, nullable=True, index=True)
    password_hash: Mapped[str | None] = mapped_column(String(128), nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)

    devices: Mapped[list[Device]] = relationship(back_populates="account")


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(String(36), ForeignKey("accounts.id"), index=True)
    display_name: Mapped[str] = mapped_column(String(120), default="Zy device")
    access_token: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    refresh_token: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    pairing_code: Mapped[str] = mapped_column(String(6), unique=True, index=True)
    access_expires_at: Mapped[float] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    account: Mapped[Account] = relationship(back_populates="devices")
    status: Mapped[DeviceStatusRow | None] = relationship(
        back_populates="device", uselist=False, cascade="all, delete-orphan"
    )


class AdminToken(Base):
    __tablename__ = "admin_tokens"

    token: Mapped[str] = mapped_column(String(128), primary_key=True)
    device_id: Mapped[str] = mapped_column(String(36), ForeignKey("devices.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    # Unix epoch seconds; NULL on legacy rows treated as expired after migration backfill.
    expires_at: Mapped[float | None] = mapped_column(Float, nullable=True)


class DeviceStatusRow(Base):
    __tablename__ = "device_status"

    device_id: Mapped[str] = mapped_column(String(36), ForeignKey("devices.id"), primary_key=True)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    device: Mapped[Device] = relationship(back_populates="status")

    def get_payload(self) -> dict[str, Any]:
        try:
            return json.loads(self.payload_json)
        except json.JSONDecodeError:
            return {}

    def set_payload(self, data: dict[str, Any]) -> None:
        self.payload_json = json.dumps(data)
        self.updated_at = utcnow()


class SyncEntity(Base):
    """Last-write-wins sync document scoped to an account."""

    __tablename__ = "sync_entities"
    __table_args__ = (
        UniqueConstraint("account_id", "entity_type", "entity_id", name="uq_sync_entity"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    account_id: Mapped[str] = mapped_column(String(36), ForeignKey("accounts.id"), index=True)
    entity_type: Mapped[str] = mapped_column(String(32), index=True)
    entity_id: Mapped[str] = mapped_column(String(64))
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    writer_device_id: Mapped[str] = mapped_column(String(36), default="")

    def get_payload(self) -> dict[str, Any]:
        try:
            return json.loads(self.payload_json)
        except json.JSONDecodeError:
            return {}

    def set_payload(self, data: dict[str, Any]) -> None:
        self.payload_json = json.dumps(data)


def ensure_account_auth_columns() -> None:
    """Add email/password/display_name on existing DBs (create_all won't alter)."""
    with engine.begin() as conn:
        if _is_sqlite:
            cols = {
                row[1]
                for row in conn.exec_driver_sql("PRAGMA table_info(accounts)").fetchall()
            }
            if "email" not in cols:
                conn.exec_driver_sql("ALTER TABLE accounts ADD COLUMN email VARCHAR(320)")
            if "password_hash" not in cols:
                conn.exec_driver_sql(
                    "ALTER TABLE accounts ADD COLUMN password_hash VARCHAR(128)"
                )
            if "display_name" not in cols:
                conn.exec_driver_sql(
                    "ALTER TABLE accounts ADD COLUMN display_name VARCHAR(120)"
                )
            conn.exec_driver_sql(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_accounts_email ON accounts (email)"
            )
        else:
            conn.exec_driver_sql(
                "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS email VARCHAR(320)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS password_hash VARCHAR(128)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE accounts ADD COLUMN IF NOT EXISTS display_name VARCHAR(120)"
            )
            conn.exec_driver_sql(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_accounts_email_unique "
                "ON accounts (email) WHERE email IS NOT NULL"
            )


def ensure_admin_token_expiry_column() -> None:
    """Add expires_at on admin_tokens for Phase 8 hardening."""
    deadline = time.time() + 86400
    with engine.begin() as conn:
        if _is_sqlite:
            cols = {
                row[1]
                for row in conn.exec_driver_sql("PRAGMA table_info(admin_tokens)").fetchall()
            }
            if "expires_at" not in cols:
                conn.exec_driver_sql("ALTER TABLE admin_tokens ADD COLUMN expires_at FLOAT")
            # Legacy tokens: grant one remaining TTL window from now.
            conn.exec_driver_sql(
                f"UPDATE admin_tokens SET expires_at = {deadline} WHERE expires_at IS NULL"
            )
        else:
            conn.exec_driver_sql(
                "ALTER TABLE admin_tokens ADD COLUMN IF NOT EXISTS expires_at DOUBLE PRECISION"
            )
            conn.exec_driver_sql(
                "UPDATE admin_tokens SET expires_at = EXTRACT(EPOCH FROM NOW()) + 86400 "
                "WHERE expires_at IS NULL"
            )


def init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    ensure_account_auth_columns()
    ensure_admin_token_expiry_column()


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
