"""セマンティック検索: クエリ埋め込み → Qdrant 検索 → SQL でドキュメント解決"""
from sqlalchemy.orm import Session

from core.config import get_settings
from core.logging import get_logger
from pipelines.enrich.embedder import embed_single
from storage.sql import repo
from storage.vector.indexes import search_vectors

logger = get_logger(__name__)
settings = get_settings()


def semantic_search(
    query: str,
    session: Session,
    top_k: int | None = None,
    score_threshold: float | None = None,
) -> list[dict]:
    """
    クエリをベクター化して近傍チャンクを検索し、ドキュメント情報付きで返す。

    Returns:
        [{"score": float, "chunk_id": str, "chunk_text": str,
          "doc_id": str, "doc_title": str, "doc_source": str}, ...]
    """
    query_vector = embed_single(query)
    results = search_vectors(
        query_vector=query_vector,
        top_k=top_k or settings.top_k,
        score_threshold=score_threshold or settings.similarity_threshold,
    )

    hits = []
    for point in results:
        payload = point.payload or {}
        doc_id = payload.get("doc_id", "")
        doc = repo.get_document(session, doc_id) if doc_id else None
        hits.append(
            {
                "score": round(point.score, 4),
                "chunk_id": payload.get("chunk_db_id", str(point.id)),
                "chunk_text": payload.get("text", ""),
                "doc_id": doc_id,
                "doc_title": doc.title if doc else "",
                "doc_source": doc.source if doc else "",
            }
        )
    return hits
