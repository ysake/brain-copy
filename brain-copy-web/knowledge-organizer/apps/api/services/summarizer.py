"""検索結果を基にした RAG スタイルの回答生成"""
from pathlib import Path

from apps.api.services.mistral_client import chat_completion
from core.config import get_settings

settings = get_settings()

_PROMPT_PATH = Path(__file__).parents[3] / "prompts" / "answer_with_citations.md"


def answer_with_context(query: str, context_chunks: list[dict]) -> str:
    """
    コンテキストチャンクを使って質問に回答する（引用付き）。

    Args:
        query: ユーザーの質問
        context_chunks: retrieval.semantic_search の結果リスト

    Returns:
        回答テキスト（引用番号付き）
    """
    system = _PROMPT_PATH.read_text(encoding="utf-8")

    # コンテキストを番号付きで整形
    context_lines = []
    for i, chunk in enumerate(context_chunks, 1):
        title = chunk.get("doc_title", "")
        text = chunk.get("chunk_text", "")
        context_lines.append(f"[{i}] {title}\n{text}")

    context_block = "\n\n".join(context_lines)
    user = f"Question: {query}\n\nContext:\n{context_block}"

    return chat_completion(
        system=system,
        user=user,
        model=settings.mistral_chat_model,
        temperature=0.2,
    )
