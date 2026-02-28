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

## サブプロジェクト: knowledge-organizer

- **役割**: テキスト投入 → チャンク分割 → Mistral 埋め込み → Qdrant 保存 → 関連づけ・要約
- **必要**: Mistral API / Qdrant（Docker またはバイナリ）/ SQLite or PostgreSQL
- **起動**: `cd knowledge-organizer` → `source venv/bin/activate` → `uvicorn apps.api.main:app --reload`
- 詳細は [knowledge-organizer/README.md](knowledge-organizer/README.md) を参照。
