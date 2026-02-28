"""POST /ingest – テキスト投入エンドポイント"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from apps.api.schemas.ingest import IngestRequest, IngestResponse
from core.config import get_settings
from core.logging import get_logger
from core.utils.hashing import sha256_hex
from pipelines.enrich.embedder import embed_texts
from pipelines.enrich.summarizer import summarize_document
from pipelines.enrich.tagger import tag_text
from pipelines.ingest.chunker import chunk_text
from pipelines.ingest.metadata import build_chunk_meta
from pipelines.ingest.text_loader import load_from_string
from pipelines.relate.graph_builder import build_relations_for_doc
from storage.sql import repo
from storage.sql.repo import db_session
from storage.vector.indexes import upsert_vectors

router = APIRouter(prefix="/ingest", tags=["ingest"])
logger = get_logger(__name__)
settings = get_settings()


@router.post("", response_model=IngestResponse)
def ingest_text(req: IngestRequest, session: Session = Depends(db_session)):
    loaded = load_from_string(req.text, title=req.title, source=req.source)
    content_hash = sha256_hex(loaded["raw_text"])

    # 重複チェック
    from storage.sql.models import Document
    from sqlalchemy import select
    existing = session.scalars(
        select(Document).where(Document.content_hash == content_hash)
    ).first()
    if existing:
        logger.info("重複ドキュメント: %s", existing.id)
        return IngestResponse(
            doc_id=existing.id,
            title=existing.title,
            chunk_count=len(existing.chunks),
            tags=existing.tags or [],
            duplicate=True,
            message="Duplicate document, skipped ingestion.",
        )

    # タグ取得（手動 or 自動）
    tags = req.tags
    if req.auto_tag and not tags:
        tags = tag_text(loaded["raw_text"])

    # 要約
    summary = None
    if req.auto_summarize:
        summary = summarize_document(loaded["raw_text"], title=req.title)

    # ドキュメント保存
    doc = repo.upsert_document(
        session,
        title=loaded["title"],
        source=loaded["source"],
        content_hash=content_hash,
        raw_text=loaded["raw_text"],
        summary=summary,
        tags=tags,
        meta={},
    )

    # チャンク分割
    raw_chunks = chunk_text(loaded["raw_text"])

    # 埋め込み生成
    texts = [c["text"] for c in raw_chunks]
    vectors = embed_texts(texts)

    # Qdrant に保存
    payloads = [
        {
            **build_chunk_meta(c["chunk_index"], doc.id),
            "text": c["text"],
            "chunk_db_id": "",  # flush後に更新
        }
        for c in raw_chunks
    ]
    vector_ids = upsert_vectors(vectors, payloads)

    # SQL にチャンク保存
    chunk_dicts = [
        {
            "document_id": doc.id,
            "chunk_index": c["chunk_index"],
            "text": c["text"],
            "token_count": c["token_count"],
            "vector_id": vid,
        }
        for c, vid in zip(raw_chunks, vector_ids)
    ]
    repo.bulk_insert_chunks(session, chunk_dicts)

    # コレクション追加
    if req.collection:
        col = repo.get_collection_by_name(session, req.collection)
        if col is None:
            col = repo.create_collection(session, req.collection)
        repo.add_to_collection(session, col.id, doc.id)

    # 関連グラフ構築
    if req.auto_relate:
        build_relations_for_doc(session, doc)

    logger.info("投入完了: doc_id=%s chunks=%d", doc.id, len(raw_chunks))
    return IngestResponse(
        doc_id=doc.id,
        title=doc.title,
        chunk_count=len(raw_chunks),
        tags=tags,
    )
