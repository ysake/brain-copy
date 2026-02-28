"""関連ドキュメント取得サービス"""
from pathlib import Path

from sqlalchemy.orm import Session

from apps.api.services.mistral_client import chat_completion
from core.config import get_settings
from core.logging import get_logger
from pipelines.enrich.embedder import embed_single
from pipelines.relate.similarity import find_similar_docs
from storage.sql import repo
from storage.sql.models import Document

logger = get_logger(__name__)
settings = get_settings()

_PROMPT_PATH = Path(__file__).parents[3] / "prompts" / "suggest_related.md"


def get_related_documents(
    doc_id: str,
    session: Session,
    top_k: int | None = None,
) -> list[dict]:
    """
    ドキュメントIDを起点に関連ドキュメントを返す。
    まず DB の Edge を参照し、なければベクター検索にフォールバック。

    Returns:
        [{"doc_id": str, "title": str, "score": float, "relation_type": str}, ...]
    """
    # まず保存済みエッジを確認
    edges = repo.get_edges_for_doc(session, doc_id)
    if edges:
        results = []
        for edge in sorted(edges, key=lambda e: e.score, reverse=True):
            other_id = edge.target_doc_id if edge.source_doc_id == doc_id else edge.source_doc_id
            other_doc = repo.get_document(session, other_id)
            if other_doc:
                results.append(
                    {
                        "doc_id": other_id,
                        "title": other_doc.title,
                        "score": round(edge.score, 4),
                        "relation_type": edge.relation_type,
                    }
                )
        return results[: top_k or settings.top_k]

    # エッジがなければベクター検索で代替
    chunks = repo.get_chunks_by_doc(session, doc_id)
    if not chunks:
        return []

    query_vector = embed_single(chunks[0].text)
    similar = find_similar_docs(
        query_vector=query_vector,
        top_k=top_k or settings.top_k,
        exclude_doc_ids=[doc_id],
    )

    results = []
    for candidate in similar:
        doc = repo.get_document(session, candidate["doc_id"])
        if doc:
            results.append(
                {
                    "doc_id": candidate["doc_id"],
                    "title": doc.title,
                    "score": round(candidate["max_score"], 4),
                    "relation_type": "similar",
                }
            )
    return results
