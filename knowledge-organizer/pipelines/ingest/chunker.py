"""固定長 + オーバーラップ でテキストをチャンクに分割する"""
import tiktoken

from core.config import get_settings

settings = get_settings()

# Mistral は cl100k_base と互換性が高い
_enc = tiktoken.get_encoding("cl100k_base")


def tokenize(text: str) -> list[int]:
    return _enc.encode(text)


def detokenize(tokens: list[int]) -> str:
    return _enc.decode(tokens)


def chunk_text(
    text: str,
    chunk_size: int | None = None,
    overlap: int | None = None,
) -> list[dict]:
    """
    テキストをトークンベースで分割する。

    Returns:
        list of {"chunk_index": int, "text": str, "token_count": int}
    """
    size = chunk_size or settings.chunk_size
    ovlp = overlap or settings.chunk_overlap

    tokens = tokenize(text)
    chunks = []
    start = 0
    idx = 0

    while start < len(tokens):
        end = min(start + size, len(tokens))
        chunk_tokens = tokens[start:end]
        chunk_text = detokenize(chunk_tokens)
        chunks.append(
            {
                "chunk_index": idx,
                "text": chunk_text,
                "token_count": len(chunk_tokens),
            }
        )
        if end == len(tokens):
            break
        start += size - ovlp
        idx += 1

    return chunks
