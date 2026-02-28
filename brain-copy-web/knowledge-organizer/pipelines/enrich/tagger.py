"""LLM を使ってトピック/キーワードタグを付与する"""
import json
from pathlib import Path

from apps.api.services.mistral_client import chat_completion
from core.config import get_settings
from core.logging import get_logger

logger = get_logger(__name__)
settings = get_settings()

_PROMPT_PATH = Path(__file__).parents[2] / "prompts" / "tag_chunks.md"


def _load_prompt() -> str:
    return _PROMPT_PATH.read_text(encoding="utf-8")


def tag_text(text: str, max_tags: int = 8) -> list[str]:
    """
    テキストからタグリストを生成する。
    LLM に JSON 配列を出力させ、パースして返す。
    """
    prompt = _load_prompt()
    user_msg = f"Max tags: {max_tags}\n\nText:\n{text[:3000]}"
    raw = chat_completion(
        system=prompt,
        user=user_msg,
        model=settings.mistral_small_model,
        temperature=0.2,
    )
    try:
        tags = json.loads(raw)
        if isinstance(tags, list):
            return [str(t).strip() for t in tags[:max_tags]]
    except (json.JSONDecodeError, ValueError):
        logger.warning("tag_text: JSONパース失敗。空タグを返します。 raw=%s", raw[:100])
    return []
