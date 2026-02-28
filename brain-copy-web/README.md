# brain-copy

## ファイル構成

```
brain-copy/
├── .gitignore
├── LICENSE
├── README.md
├── app.js
├── index.html
├── style.css
├── kmeans.js
├── requirements.txt
├── generate_massive_texts.py
├── text_to_cluster_csv.py
├── texts.txt
├── cluster_points.csv
├── cluster_points_接続分析.txt
├── cluster_points_距離の基準.txt
│
└── knowledge-organizer/          # ナレッジオーガナイザー（テキスト投入→関連づけ→まとめ）
    ├── .env.example
    ├── .env                      # 要設定（MISTRAL_API_KEY 等）
    ├── README.md
    ├── pyproject.toml
    │
    ├── apps/
    │   └── api/
    │       ├── main.py           # FastAPI エントリポイント
    │       ├── routers/          # ルート定義
    │       │   ├── collections.py
    │       │   ├── ingest_text.py
    │       │   ├── related.py
    │       │   ├── search.py
    │       │   └── summarize.py
    │       ├── schemas/          # リクエスト/レスポンス型
    │       │   ├── ingest.py
    │       │   ├── result.py
    │       │   └── search.py
    │       └── services/        # API 用サービス
    │           ├── mistral_client.py
    │           ├── relate.py
    │           ├── retrieval.py
    │           └── summarizer.py
    │
    ├── core/
    │   ├── config.py            # 設定（環境変数）
    │   ├── logging.py
    │   └── utils/
    │       ├── hashing.py
    │       └── text_clean.py
    │
    ├── pipelines/
    │   ├── ingest/              # テキスト取り込み
    │   │   ├── chunker.py
    │   │   ├── metadata.py
    │   │   └── text_loader.py
    │   ├── enrich/              # 埋め込み・要約・タグ
    │   │   ├── embedder.py
    │   │   ├── summarizer.py
    │   │   └── tagger.py
    │   └── relate/              # 関連づけ
    │       ├── cluster.py
    │       ├── graph_builder.py
    │       └── similarity.py
    │
    ├── storage/
    │   ├── sql/                 # SQLite / PostgreSQL
    │   │   ├── models.py
    │   │   ├── repo.py
    │   │   └── migrations/
    │   └── vector/              # Qdrant
    │       ├── client.py
    │       └── indexes.py
    │
    └── prompts/                # LLM プロンプト（Markdown）
        ├── answer_with_citations.md
        ├── summarize_cluster.md
        ├── summarize_doc.md
        └── tag_chunks.md
```

## 個人URLの投稿を texts.txt に取り込む（Mistral Websearch）

指定したURL（ブログ・Notion・個人サイトなど）の投稿を [Mistral Websearch](https://docs.mistral.ai/agents/tools/built-in/websearch) で検索し、`texts.txt` に追記できます。

```bash
cd brain-copy-web
./knowledge-organizer/venv/bin/python3 fetch_posts_to_texts.py --url "https://example.com/blog"
```

- **環境変数**: `PERSON_BASE_URL` を設定すると `--url` を省略可能（`knowledge-organizer/.env` に `PERSON_BASE_URL=https://...` を追加）
- **追記／上書き**: デフォルトは追記。`--replace` で既存の `texts.txt` を上書き
- **APIキー**: `MISTRAL_API_KEY` を `.env` に設定（同上）

取り込み後、`text_to_cluster_csv.py` で `cluster_points.csv` を再生成し、`index.html` でマップを更新できます。

## texts を複数パターンで分ける（案1: 同じフォルダでファイル名で分ける）

1行1テキストのデータを用途別に持ちたいときは、同じフォルダでファイル名だけ分けます。クラスタは従来どおり `cluster_points.csv` に出力し、必要に応じてコピーして格納します。

| ファイル名 | 用途 |
|------------|------|
| `texts.txt` | メイン（クラスタ用に使う1本） |
| `texts_arisan_lig.txt` | LIG 著者ページから取得（`--output` で指定） |
| `texts_x_arisan.txt` | X 用（`--output` で指定） |
| `texts_manual.txt` | 手動で編集・追記する用 |

**例**

```bash
# パターン用の texts を作成
./knowledge-organizer/venv/bin/python3 fetch_author_links_to_texts.py --url "https://liginc.co.jp/author/arisan" --output texts_arisan_lig.txt --replace

# その texts で cluster_points.csv を生成（必要なら CSV をコピーして別名で保存）
./knowledge-organizer/venv/bin/python3 text_to_cluster_csv.py -i texts_arisan_lig.txt -o cluster_points.csv
```

## サブプロジェクト: knowledge-organizer

- **役割**: テキスト投入 → チャンク分割 → Mistral 埋め込み → Qdrant 保存 → 関連づけ・要約
- **必要**: Mistral API / Qdrant（Docker またはバイナリ）/ SQLite or PostgreSQL
- **起動**: `cd knowledge-organizer` → `source venv/bin/activate` → `uvicorn apps.api.main:app --reload`
- 詳細は [knowledge-organizer/README.md](knowledge-organizer/README.md) を参照。
