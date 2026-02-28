#!/usr/bin/env python3
"""
著者ページの記事一覧を取得し、各記事リンク先の本文も取得して texts.txt に追記する。

- 著者ページから記事タイトル＋URLの一覧を取得
- 各URLにアクセスして本文（タイトル・段落・見出し）を取得
- 1行1テキストで texts.txt に追記（タイトル行＋本文の段落など）

使い方:
  python3 fetch_author_links_to_texts.py --url "https://liginc.co.jp/author/arisan"
  python3 fetch_author_links_to_texts.py --url "https://liginc.co.jp/author/arisan" --output texts.txt --replace
"""

import argparse
import re
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

# 1リクエストあたりの間隔（秒）。サーバーに優しく
FETCH_DELAY = 1.0

# 本文として扱うタグ
CONTENT_TAGS = ["p", "h1", "h2", "h3", "h4", "li"]
# 本文コンテナの候補クラス・タグ（先にマッチしたものを使う）
CONTENT_SELECTORS = [
    "article .entry-content",
    "article .post-content",
    ".post-content",
    ".entry-content",
    ".article-body",
    "article",
    "main",
]


def get_soup(url: str, session: requests.Session) -> BeautifulSoup | None:
    try:
        r = session.get(url, timeout=15, headers={"User-Agent": "Mozilla/5.0 (compatible; fetch_author_links/1.0)"})
        r.raise_for_status()
        r.encoding = r.apparent_encoding or "utf-8"
        return BeautifulSoup(r.text, "html.parser")
    except Exception as e:
        print(f"  [skip] {url}: {e}")
        return None


def _normalize_url(u: str) -> str:
    parsed = urlparse(u)
    path = parsed.path.rstrip("/") or "/"
    return f"{parsed.scheme}://{parsed.netloc}{path}"


def extract_article_links(soup: BeautifulSoup, base_url: str, domain: str) -> list[tuple[str, str]]:
    """著者ページから記事の (タイトル, URL) のリストを取得"""
    base_domain = urlparse(base_url).netloc
    base_norm = _normalize_url(base_url)
    seen = set()
    links = []
    for a in soup.find_all("a", href=True):
        href = a.get("href", "").strip()
        if not href or href.startswith("#"):
            continue
        full_url = urljoin(base_url, href)
        parsed = urlparse(full_url)
        if parsed.netloc != base_domain:
            continue
        if _normalize_url(full_url) == base_norm:
            continue  # 著者ページ自身は除外
        text = (a.get_text() or "").strip()
        if len(text) < 5:
            continue
        if re.match(r"^[\d\.\/\-]+$", text) or text in ("ありさん", "続きを読む", "Read more", "PR"):
            continue
        if full_url in seen:
            continue
        seen.add(full_url)
        links.append((text[:200], full_url))
    return links


def extract_page_content(soup: BeautifulSoup) -> list[str]:
    """1ページから本文テキストのリストを取得（タイトル＋段落・見出し）"""
    lines = []
    # タイトル
    for tag in ["h1", "title"]:
        el = soup.find(tag)
        if el:
            t = (el.get_text() or "").strip()
            if t and len(t) > 2:
                lines.append(t[:500])
                break
    # 本文コンテナを探す
    body = None
    for sel in CONTENT_SELECTORS:
        body = soup.select_one(sel)
        if body:
            break
    if not body:
        body = soup.find("body")
    if not body:
        return lines
    for tag in CONTENT_TAGS:
        for el in body.find_all(tag):
            t = (el.get_text() or "").strip()
            if not t or len(t) < 10:
                continue
            # 1行が長い場合は適度に分割（クラスタ用に扱いやすく）
            if len(t) > 300:
                for chunk in re.split(r"[。\n]+", t):
                    chunk = chunk.strip()
                    if len(chunk) >= 10:
                        lines.append(chunk[:500])
            else:
                lines.append(t[:500])
    return lines


def main():
    parser = argparse.ArgumentParser(
        description="著者ページの記事一覧を取得し、各リンク先の本文も取得して texts.txt に追記します。"
    )
    parser.add_argument("--url", "-u", required=True, help="著者ページのURL（例: https://liginc.co.jp/author/arisan）")
    parser.add_argument("--output", "-o", default="texts.txt", help="出力ファイル（デフォルト: texts.txt）")
    parser.add_argument("--replace", action="store_true", help="既存ファイルを上書きする。指定しない場合は追記。")
    parser.add_argument("--max-articles", type=int, default=100, help="取得する記事数の上限（デフォルト: 100）")
    args = parser.parse_args()

    base_url = args.url.strip()
    domain = urlparse(base_url).netloc
    session = requests.Session()

    print(f"著者ページを取得: {base_url}")
    soup = get_soup(base_url, session)
    if not soup:
        print("著者ページの取得に失敗しました。")
        return
    links = extract_article_links(soup, base_url, domain)
    # 重複タイトルで同じURLのものは1本に
    by_url = {}
    for title, url in links:
        if url not in by_url or len(title) > len(by_url[url][0]):
            by_url[url] = (title, url)
    links = list(by_url.values())[: args.max_articles]
    print(f"記事リンクを {len(links)} 件取得しました。")

    all_lines = []
    for i, (title, url) in enumerate(links, 1):
        print(f"  [{i}/{len(links)}] {url[:60]}...")
        time.sleep(FETCH_DELAY)
        page_soup = get_soup(url, session)
        if not page_soup:
            all_lines.append(title)  # タイトルのみ
            continue
        content = extract_page_content(page_soup)
        if content:
            all_lines.append(content[0] if content[0] else title)  # 1行目はタイトル
            for line in content[1:]:
                if line and line not in all_lines:
                    all_lines.append(line)
        else:
            all_lines.append(title)

    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    outpath = os.path.join(script_dir, args.output)
    mode = "w" if args.replace else "a"
    need_newline = not args.replace and os.path.isfile(outpath) and os.path.getsize(outpath) > 0
    with open(outpath, mode, encoding="utf-8") as f:
        if need_newline:
            f.write("\n")
        f.write("\n".join(all_lines))
        f.write("\n")

    print(f"{len(all_lines)} 行を {outpath} に{'上書き' if args.replace else '追記'}しました。")


if __name__ == "__main__":
    main()
