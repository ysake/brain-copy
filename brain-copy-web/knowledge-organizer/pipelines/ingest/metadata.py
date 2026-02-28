"""メタデータの構築・バリデーション"""
from datetime import datetime


def build_doc_meta(
    title: str,
    source: str | None = None,
    tags: list[str] | None = None,
    extra: dict | None = None,
) -> dict:
    """ドキュメントメタデータを構築する"""
    meta: dict = {"ingested_at": datetime.utcnow().isoformat()}
    if extra:
        meta.update(extra)
    return {
        "title": title,
        "source": source,
        "tags": tags or [],
        "meta": meta,
    }


def build_chunk_meta(chunk_index: int, doc_id: str, extra: dict | None = None) -> dict:
    """チャンクメタデータを構築する（Qdrant payload にも使用）"""
    meta: dict = {"chunk_index": chunk_index, "doc_id": doc_id}
    if extra:
        meta.update(extra)
    return meta
