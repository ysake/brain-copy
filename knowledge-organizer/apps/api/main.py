"""FastAPI アプリケーションのエントリポイント"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from apps.api.routers import collections, ingest_text, related, search, summarize
from core.config import get_settings
from core.logging import setup_logging
from storage.sql.repo import init_db
from storage.vector.client import ensure_collection_exists

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    init_db()
    ensure_collection_exists()
    yield


app = FastAPI(
    title="Knowledge Organizer API",
    description="テキスト投入 → 関連づけ → まとめ の最小ナレッジオーガナイザー",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(ingest_text.router)
app.include_router(search.router)
app.include_router(related.router)
app.include_router(summarize.router)
app.include_router(collections.router)


@app.get("/health")
def health():
    return {"status": "ok"}
