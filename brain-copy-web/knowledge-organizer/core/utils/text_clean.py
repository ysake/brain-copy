import re
import unicodedata


def normalize(text: str) -> str:
    """Unicode正規化 + 基本的なホワイトスペース整理"""
    text = unicodedata.normalize("NFKC", text)
    # 連続する空白・タブを単一スペースに
    text = re.sub(r"[ \t]+", " ", text)
    # 3行以上の連続改行を2行に
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def remove_control_chars(text: str) -> str:
    """制御文字を除去（改行・タブは保持）"""
    return re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)


def clean(text: str) -> str:
    """投入テキストの標準クリーニングパイプライン"""
    text = remove_control_chars(text)
    text = normalize(text)
    return text
