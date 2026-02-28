"""類似候補から Edge を SQL に保存するグラフ構築処理"""
from sqlalchemy.orm import Session

from core.config import get_settings
from core.logging import get_logger
from pipelines.enrich.embedder import embed_single
from pipelines.relate.similarity import find_similar_docs
from storage.sql import repo
from storage.sql.models import Document

logger = get_logger(__name__)
settings = get_settings()


def build_relations_for_doc(session: Session, doc: Document) -> int:
    """
    1ドキュメントに対して関連ドキュメントを探し、Edge を保存する。

    Returns:
        作成・更新したエッジ数
    """
    # ドキュメントの代表ベクター: 先頭チャンクを埋め込む
    chunks = repo.get_chunks_by_doc(session, doc.id)
    if not chunks:
        logger.warning("doc %s にチャンクがありません", doc.id)
        return 0

    # 先頭チャンクの埋め込みを代表ベクターとして使用
    query_vector = embed_single(chunks[0].text)

    similar = find_similar_docs(
        query_vector=query_vector,
        top_k=settings.relation_top_k,
        exclude_doc_ids=[doc.id],
    )

    count = 0
    for candidate in similar:
        target_id = candidate["doc_id"]
        score = candidate["max_score"]
        if score < settings.relation_threshold:
            continue
        repo.upsert_edge(session, doc.id, target_id, score)
        count += 1

    logger.info("doc %s → %d エッジを構築", doc.id, count)
    return count


def rebuild_all_relations(session: Session) -> int:
    """全ドキュメントに対してリレーション再構築"""
    docs = repo.list_documents(session, limit=10000)
    total = 0
    for doc in docs:
        total += build_relations_for_doc(session, doc)
    return total
