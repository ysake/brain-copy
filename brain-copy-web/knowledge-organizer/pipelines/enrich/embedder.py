"""Mistral embeddings API を呼び出してベクターを生成する"""
from apps.api.services.mistral_client import get_mistral_client
from core.config import get_settings

settings = get_settings()


def embed_texts(texts: list[str]) -> list[list[float]]:
    """
    テキストリストを埋め込みベクターに変換する。
    Mistral API は最大 2048 トークン / テキスト。
    """
    client = get_mistral_client()
    response = client.embeddings.create(
        model=settings.mistral_embed_model,
        inputs=texts,
    )
    # response.data は EmbeddingObject のリスト（順序保証あり）
    return [item.embedding for item in response.data]


def embed_single(text: str) -> list[float]:
    return embed_texts([text])[0]
