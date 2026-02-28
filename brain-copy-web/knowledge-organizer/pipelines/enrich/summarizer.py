"""LLM を使ってドキュメント/チャンク/クラスターを要約する"""
from pathlib import Path

from apps.api.services.mistral_client import chat_completion
from core.config import get_settings

settings = get_settings()

_PROMPTS_DIR = Path(__file__).parents[2] / "prompts"


def _load(filename: str) -> str:
    return (_PROMPTS_DIR / filename).read_text(encoding="utf-8")


def summarize_document(text: str, title: str = "") -> str:
    """ドキュメント全体の要約"""
    system = _load("summarize_doc.md")
    user = f"Title: {title}\n\nText:\n{text[:6000]}"
    return chat_completion(system=system, user=user, model=settings.mistral_chat_model)


def summarize_chunks(chunks: list[str]) -> str:
    """複数チャンクを結合して要約（クラスター要約用）"""
    system = _load("summarize_cluster.md")
    combined = "\n\n---\n\n".join(chunks[:10])  # 多すぎる場合は先頭10件
    return chat_completion(system=system, user=combined, model=settings.mistral_chat_model)


def summarize_chunk(text: str) -> str:
    """単一チャンクの短い要約（インデックス用）"""
    system = "You are a concise summarizer. Summarize the following text in 1-2 sentences."
    return chat_completion(system=system, user=text[:2000], model=settings.mistral_small_model)
