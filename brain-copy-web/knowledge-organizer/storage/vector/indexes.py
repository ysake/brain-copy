"""Qdrant への upsert / 検索ラッパー"""
import uuid
from typing import Any

from qdrant_client.http.models import PointStruct, ScoredPoint, Filter

from core.config import get_settings
from storage.vector.client import get_qdrant

settings = get_settings()


def upsert_vectors(
    vectors: list[list[float]],
    payloads: list[dict[str, Any]],
    ids: list[str] | None = None,
) -> list[str]:
    """ベクターを Qdrant に保存し、point id のリストを返す"""
    client = get_qdrant()
    if ids is None:
        ids = [str(uuid.uuid4()) for _ in vectors]

    points = [
        PointStruct(id=pid, vector=vec, payload=payload)
        for pid, vec, payload in zip(ids, vectors, payloads)
    ]
    client.upsert(collection_name=settings.qdrant_collection, points=points)
    return ids


def search_vectors(
    query_vector: list[float],
    top_k: int | None = None,
    score_threshold: float | None = None,
    filter_: Filter | None = None,
) -> list[ScoredPoint]:
    """近傍ベクターを検索して ScoredPoint のリストを返す"""
    client = get_qdrant()
    k = top_k or settings.top_k
    results = client.search(
        collection_name=settings.qdrant_collection,
        query_vector=query_vector,
        limit=k,
        score_threshold=score_threshold or settings.similarity_threshold,
        query_filter=filter_,
        with_payload=True,
    )
    return results


def delete_vectors(ids: list[str]) -> None:
    client = get_qdrant()
    client.delete(
        collection_name=settings.qdrant_collection,
        points_selector=ids,
    )
