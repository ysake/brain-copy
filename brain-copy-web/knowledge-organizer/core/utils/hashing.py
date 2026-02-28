import hashlib


def sha256_hex(text: str) -> str:
    """テキストの SHA-256 ハッシュを返す（重複排除用）"""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def short_hash(text: str, length: int = 8) -> str:
    """短縮ハッシュ（ログ表示用）"""
    return sha256_hex(text)[:length]
