"""Qdrant クライアントのシングルトン"""
from functools import lru_cache

from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams

from core.config import get_settings

settings = get_settings()


@lru_cache
def get_qdrant() -> QdrantClient:
    if settings.qdrant_path:
        return QdrantClient(path=settings.qdrant_path)
    return QdrantClient(host=settings.qdrant_host, port=settings.qdrant_port)


def ensure_collection_exists() -> None:
    """コレクションが存在しない場合のみ作成"""
    client = get_qdrant()
    existing = [c.name for c in client.get_collections().collections]
    if settings.qdrant_collection not in existing:
        client.create_collection(
            collection_name=settings.qdrant_collection,
            vectors_config=VectorParams(
                size=settings.vector_dim,
                distance=Distance.COSINE,
            ),
        )
