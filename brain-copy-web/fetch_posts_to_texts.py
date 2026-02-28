#!/usr/bin/env python3
"""
指定URLの投稿・記事を Mistral Websearch で取得し、texts.txt に追記するスクリプト。

Mistral Agents の Websearch ツールを使用:
  https://docs.mistral.ai/agents/tools/built-in/websearch

使い方:
  python3 fetch_posts_to_texts.py --url "https://example.com/blog"
  python3 fetch_posts_to_texts.py --url "https://example.com" --output texts.txt --replace

環境変数:
  MISTRAL_API_KEY  … 必須（.env または knowledge-organizer/.env から読む）
  PERSON_BASE_URL  … --url 未指定時に使用
"""

import argparse
import os
import re
from typing import List

try:
    from dotenv import load_dotenv
    _script_dir = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(_script_dir, ".env"))
    load_dotenv(os.path.join(_script_dir, "knowledge-organizer", ".env"))
    load_dotenv()
except ImportError:
    pass


def get_mistral_client():
    from mistralai import Mistral
    api_key = os.getenv("MISTRAL_API_KEY")
    if not api_key:
        raise RuntimeError(
            "MISTRAL_API_KEY が設定されていません。.env または環境変数を設定してください。"
        )
    return Mistral(api_key=api_key)


def extract_text_from_outputs(outputs: List) -> str:
    """conversation response の outputs からテキストを結合して返す"""
    parts = []
    for out in outputs or []:
        content = out.get("content") if isinstance(out, dict) else getattr(out, "content", None)
        if content is None:
            continue
        if isinstance(content, str):
            parts.append(content)
            continue
        if isinstance(content, list):
            for chunk in content:
                if isinstance(chunk, dict):
                    if chunk.get("type") == "text" and "text" in chunk:
                        parts.append(chunk["text"])
                elif hasattr(chunk, "type") and getattr(chunk, "type") == "text":
                    parts.append(getattr(chunk, "text", "") or "")
    return "\n".join(parts)


def fetch_posts_with_websearch(client, url: str, model: str = "mistral-large-latest") -> List[str]:
    """
    Mistral Websearch で指定URLの投稿・記事タイトル一覧を取得する。
    返り値: 1行1件の文字列リスト
    """
    instructions = (
        "You have the ability to perform web searches with web_search. "
        "When asked for posts or articles from a URL, search the web for that site and list "
        "each post title or short content summary. Output only the list: one item per line, "
        "no numbering, no extra explanation. Use the language of the source when possible."
    )
    prompt = (
        f"Search the web for recent posts, articles, or page titles from this URL/site: {url}. "
        "List each post or article title (or a one-line summary) on a single line. "
        "Output only the list, one item per line, no numbering or bullets."
    )
    response = client.beta.conversations.start(
        inputs=prompt,
        stream=False,
        model=model,
        instructions=instructions,
        tools=[{"type": "web_search"}],
    )

    # レスポンスからテキスト抽出（outputs または entries）
    outputs = list(getattr(response, "outputs", None) or getattr(response, "data", None) or [])
    if not outputs and hasattr(response, "entries"):
        for entry in response.entries or []:
            etype = getattr(entry, "type", None) or (entry.get("type") if isinstance(entry, dict) else None)
            if etype == "message.output":
                content = getattr(entry, "content", None) or (entry.get("content") if isinstance(entry, dict) else None)
                if content:
                    outputs.append({"content": content})
    text = extract_text_from_outputs(outputs if outputs else [response])

    # 1行1件にパース（番号・箇条書きを除去）
    lines = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        # 先頭の "1. " "・ " "- " などを除去
        line = re.sub(r"^[\d]+[\.\)\s]+\s*", "", line)
        line = re.sub(r"^[・\-*]\s*", "", line)
        if len(line) > 5:  # 短すぎる行はノイズの可能性
            lines.append(line)
    return lines


def main():
    parser = argparse.ArgumentParser(
        description="指定URLの投稿を Mistral Websearch で取得し、texts.txt に追記します。"
    )
    parser.add_argument(
        "--url", "-u",
        default=os.getenv("PERSON_BASE_URL"),
        help="取得対象のURL（例: ブログ・Notion・個人サイト）。未指定時は PERSON_BASE_URL を使用。",
    )
    parser.add_argument(
        "--output", "-o",
        default="texts.txt",
        help="出力テキストファイル（デフォルト: texts.txt）",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="既存ファイルを上書きする。指定しない場合は追記。",
    )
    parser.add_argument(
        "--model", "-m",
        default="mistral-large-latest",
        help="Mistral チャットモデル（デフォルト: mistral-large-latest）",
    )
    args = parser.parse_args()

    if not args.url or not args.url.strip():
        parser.error("--url または環境変数 PERSON_BASE_URL を設定してください。")

    url = args.url.strip()
    print(f"URL: {url}")
    print("Mistral Websearch で投稿を取得しています...")

    client = get_mistral_client()
    lines = fetch_posts_with_websearch(client, url, model=args.model)

    if not lines:
        print("取得できた行がありません。")
        return

    outpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output)
    mode = "w" if args.replace else "a"
    with open(outpath, mode, encoding="utf-8") as f:
        if not args.replace and os.path.getsize(outpath) > 0:
            f.write("\n")
        f.write("\n".join(lines))
        f.write("\n")

    print(f"{len(lines)} 件を {outpath} に{'上書き' if args.replace else '追記'}しました。")


if __name__ == "__main__":
    main()
