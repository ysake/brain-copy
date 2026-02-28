"""Mistral API クライアントのシングルトンと便利ラッパー"""
from functools import lru_cache

from mistralai import Mistral
from mistralai.models import UserMessage, SystemMessage

from core.config import get_settings

settings = get_settings()


@lru_cache
def get_mistral_client() -> Mistral:
    return Mistral(api_key=settings.mistral_api_key)


def chat_completion(
    user: str,
    system: str | None = None,
    model: str | None = None,
    temperature: float = 0.3,
    max_tokens: int = 2048,
) -> str:
    """チャット補完を実行してアシスタントの返答テキストを返す"""
    client = get_mistral_client()
    messages = []
    if system:
        messages.append(SystemMessage(content=system))
    messages.append(UserMessage(content=user))

    response = client.chat.complete(
        model=model or settings.mistral_chat_model,
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
    )
    return response.choices[0].message.content or ""
