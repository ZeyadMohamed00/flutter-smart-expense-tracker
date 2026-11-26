"""Sync backend for the Smart Expense Tracker. One endpoint: POST /sync (push changes, pull newer ones)."""
import os
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, text

engine = create_engine(os.getenv("DATABASE_URL", "postgresql+psycopg2://postgres@localhost/exp"), pool_pre_ping=True)


class Change(BaseModel):
    id: str = Field(min_length=1, max_length=80)
    cents: int = Field(ge=0, le=10**12)
    category: str = Field(max_length=60)
    note: str = Field(max_length=300)
    date: int
    is_income: bool
    updated_at: int
    deleted: bool


class SyncIn(BaseModel):
    since: int = Field(default=0, ge=0)
    changes: list[Change] = Field(default_factory=list, max_length=500)


def init():
    with engine.begin() as c:
        c.execute(text("SELECT pg_advisory_xact_lock(424242)"))
        c.execute(text("CREATE SEQUENCE IF NOT EXISTS exp_seq"))
        c.execute(text("""CREATE TABLE IF NOT EXISTS exp_expenses(
            user_id TEXT, id TEXT, cents BIGINT, category TEXT, note TEXT, date BIGINT, is_income BOOLEAN,
            updated_at BIGINT, deleted BOOLEAN, seq BIGINT, PRIMARY KEY(user_id, id))"""))


def create_app():
    init()
    app = FastAPI(title="Smart Expense sync API", version="1.0.0")
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.post("/sync")
    def sync(b: SyncIn, x_user_id: str = Header(default="")):
        if not (3 <= len(x_user_id) <= 64):
            raise HTTPException(400, "Missing or invalid X-User-Id header")
        with engine.begin() as c:
            for ch in b.changes:
                # last-write-wins: only overwrite when the incoming edit is strictly newer
                c.execute(text("""INSERT INTO exp_expenses(user_id,id,cents,category,note,date,is_income,updated_at,deleted,seq)
                    VALUES(:u,:id,:cents,:category,:note,:date,:is_income,:updated_at,:deleted,nextval('exp_seq'))
                    ON CONFLICT(user_id,id) DO UPDATE SET cents=EXCLUDED.cents, category=EXCLUDED.category, note=EXCLUDED.note,
                      date=EXCLUDED.date, is_income=EXCLUDED.is_income, updated_at=EXCLUDED.updated_at, deleted=EXCLUDED.deleted, seq=EXCLUDED.seq
                    WHERE exp_expenses.updated_at < EXCLUDED.updated_at"""), {"u": x_user_id, **ch.model_dump()})
            rows = c.execute(text("SELECT id,cents,category,note,date,is_income,updated_at,deleted,seq FROM exp_expenses WHERE user_id=:u AND seq>:s ORDER BY seq LIMIT 1000"),
                             {"u": x_user_id, "s": b.since}).mappings().all()
        cursor = max([r["seq"] for r in rows], default=b.since)
        return {"server_time": cursor, "changes": [{k: r[k] for k in ("id", "cents", "category", "note", "date", "is_income", "updated_at", "deleted")} for r in rows]}

    return app


app = create_app()
