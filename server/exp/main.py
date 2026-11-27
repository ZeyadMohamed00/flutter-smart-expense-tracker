"""Sync backend for the Smart Expense Tracker. One endpoint: POST /sync (push changes, pull newer ones)."""
import os
import time
import hashlib, hmac, re, secrets
from collections import deque
from datetime import datetime, timedelta, timezone

import jwt
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


class Credentials(BaseModel):
    email: str = Field(max_length=200)
    password: str = Field(min_length=8, max_length=128)
    name: str = Field(default="", max_length=120)


class LoginIn(BaseModel):
    email: str = Field(max_length=200)
    password: str = Field(max_length=128)


ITERATIONS = 200_000


_FAILS: dict = {}
MAX_FAILS = int(os.getenv("LOGIN_MAX_FAILS", "5"))
FAIL_WINDOW = int(os.getenv("LOGIN_FAIL_WINDOW_S", "300"))


def _recent_fails(email):
    q = _FAILS.setdefault(email, deque())
    now = time.time()
    while q and now - q[0] > FAIL_WINDOW:
        q.popleft()
    return q


def _secret():
    if not os.getenv("JWT_SECRET") and os.getenv("APP_ENV") == "production":
        raise RuntimeError("JWT_SECRET must be set when APP_ENV=production")
    return os.getenv("JWT_SECRET") or hashlib.sha256(("jwt:" + os.getenv("DATABASE_URL", "local-dev-only")).encode()).hexdigest()


def hash_password(pw):
    salt = secrets.token_bytes(16)
    return f"{salt.hex()}${hashlib.pbkdf2_hmac('sha256', pw.encode(), salt, ITERATIONS).hex()}"


def verify_password(pw, stored):
    salt, dk = stored.split("$")
    return hmac.compare_digest(hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), ITERATIONS).hex(), dk)


def token_for(uid):
    exp = datetime.now(timezone.utc) + timedelta(days=30)
    return jwt.encode({"sub": str(uid), "exp": exp}, _secret(), algorithm="HS256")


def owner_key(authorization, x_user_id):
    """`user:<id>` for a signed-in account, else the anonymous device id."""
    if authorization:
        scheme, _, tok = authorization.partition(" ")
        try:
            if scheme.lower() != "bearer":
                raise ValueError
            return f"user:{int(jwt.decode(tok, _secret(), algorithms=['HS256'])['sub'])}"
        except (jwt.PyJWTError, ValueError):
            raise HTTPException(401, "Session expired or invalid, please log in again") from None
    if not (3 <= len(x_user_id) <= 64) or ":" in x_user_id:
        raise HTTPException(400, "Missing or invalid X-User-Id header")
    return x_user_id


class SyncIn(BaseModel):
    since: int = Field(default=0, ge=0)
    changes: list[Change] = Field(default_factory=list, max_length=500)


def init():
    with engine.begin() as c:
        c.execute(text("SELECT pg_advisory_xact_lock(424242)"))
        c.execute(text("CREATE SEQUENCE IF NOT EXISTS exp_seq"))
        c.execute(text("""CREATE TABLE IF NOT EXISTS exp_users(
            id SERIAL PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT, password_hash TEXT NOT NULL)"""))
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

    def _out(uid, email, name):
        return {"access_token": token_for(uid), "token_type": "bearer", "user": {"id": uid, "email": email, "name": name}}

    @app.post("/auth/register", status_code=201)
    def register(b: Credentials):
        email = b.email.strip().lower()
        if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email):
            raise HTTPException(422, "Enter a valid email address")
        with engine.begin() as c:
            if c.execute(text("SELECT 1 FROM exp_users WHERE email=:e"), {"e": email}).first():
                raise HTTPException(409, "Email already registered")
            uid = c.execute(text("INSERT INTO exp_users(email,name,password_hash) VALUES(:e,:n,:p) RETURNING id"),
                            {"e": email, "n": b.name.strip(), "p": hash_password(b.password)}).scalar()
        return _out(uid, email, b.name.strip())

    @app.post("/auth/login")
    def login(b: LoginIn):
        email = b.email.strip().lower()
        fails = _recent_fails(email)
        if len(fails) >= MAX_FAILS:
            raise HTTPException(429, "Too many failed logins, try again later", headers={"Retry-After": str(FAIL_WINDOW)})
        with engine.begin() as c:
            r = c.execute(text("SELECT id,name,password_hash FROM exp_users WHERE email=:e"), {"e": email}).first()
        if not r or not verify_password(b.password, r[2]):
            fails.append(time.time())
            raise HTTPException(401, "Wrong email or password")
        return _out(r[0], email, r[1] or "")

    @app.get("/auth/me")
    def me(authorization: str = Header(default=""), x_user_id: str = Header(default="")):
        owner = owner_key(authorization, x_user_id)
        if not owner.startswith("user:"):
            raise HTTPException(401, "Not signed in")
        with engine.begin() as c:
            r = c.execute(text("SELECT id,email,name FROM exp_users WHERE id=:i"), {"i": int(owner[5:])}).first()
        if not r:
            raise HTTPException(401, "Account not found")
        return {"id": r[0], "email": r[1], "name": r[2] or ""}

    @app.post("/sync")
    def sync(b: SyncIn, authorization: str = Header(default=""), x_user_id: str = Header(default="")):
        x_user_id = owner_key(authorization, x_user_id)
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
