from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── Mistral ──────────────────────────────────
    mistral_api_key: str
    mistral_embed_model: str = "mistral-embed"
    mistral_chat_model: str = "mistral-large-latest"
    mistral_small_model: str = "mistral-small-latest"

    # ── Database ─────────────────────────────────
    database_url: str = "sqlite:///./knowledge.db"

    # ── Vector DB ────────────────────────────────
    qdrant_host: str = "localhost"
    qdrant_port: int = 6333
    qdrant_collection: str = "knowledge_chunks"
    vector_dim: int = 1024  # mistral-embed の次元数

    # ── Chunking ─────────────────────────────────
    chunk_size: int = 512    # tokens
    chunk_overlap: int = 64  # tokens

    # ── Retrieval ────────────────────────────────
    top_k: int = 5
    similarity_threshold: float = 0.75

    # ── Relation ─────────────────────────────────
    relation_top_k: int = 10
    relation_threshold: float = 0.80


@lru_cache
def get_settings() -> Settings:
    return Settings()
