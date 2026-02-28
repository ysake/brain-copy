"""生テキストを受け取り、クリーニング済みテキストと基本メタデータを返す"""
from pathlib import Path

from core.utils.text_clean import clean


def load_from_string(text: str, title: str = "untitled", source: str | None = None) -> dict:
    """文字列から直接ロード"""
    cleaned = clean(text)
    return {"raw_text": cleaned, "title": title, "source": source}


def load_from_file(path: str | Path, title: str | None = None) -> dict:
    """ファイルからロード（UTF-8 テキストのみ）"""
    p = Path(path)
    raw = p.read_text(encoding="utf-8")
    return load_from_string(
        text=raw,
        title=title or p.stem,
        source=str(p.resolve()),
    )
