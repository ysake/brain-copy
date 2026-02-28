"""ベクター近傍検索を使ってドキュメント間の類似候補を探す"""
from storage.vector.indexes import search_vectors
from core.config import get_settings

settings = get_settings()


def find_similar_docs(
    query_vector: list[float],
    top_k: int | None = None,
    exclude_doc_ids: list[str] | None = None,
) -> list[dict]:
    """
    クエリベクターに近いチャンクを検索し、ドキュメント単位で集約して返す。

    Returns:
        [{"doc_id": str, "max_score": float, "chunk_ids": list[str]}, ...]
    """
    k = top_k or settings.relation_top_k
    results = search_vectors(
        query_vector=query_vector,
        top_k=k * 3,  # チャンク単位なので多めに取得してから集約
        score_threshold=settings.relation_threshold,
    )

    # チャンク → ドキュメント集約
    doc_map: dict[str, dict] = {}
    for point in results:
        doc_id = point.payload.get("doc_id", "")
        if exclude_doc_ids and doc_id in exclude_doc_ids:
            continue
        if doc_id not in doc_map:
            doc_map[doc_id] = {"doc_id": doc_id, "max_score": point.score, "chunk_ids": []}
        doc_map[doc_id]["chunk_ids"].append(str(point.id))
        doc_map[doc_id]["max_score"] = max(doc_map[doc_id]["max_score"], point.score)

    # スコア降順ソート
    sorted_docs = sorted(doc_map.values(), key=lambda x: x["max_score"], reverse=True)
    return sorted_docs[:k]
