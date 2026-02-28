# knowledge-organizer

テキスト投入 → 関連づけ → まとめ の最小構成ナレッジオーガナイザー（Mistral API前提）

## アーキテクチャ

```
テキスト投入 → チャンク分割 → Mistral埋め込み → Qdrant保存
                                                    ↓
                              タグ付け(LLM) ← テキスト要約(LLM)
                                                    ↓
                                            関連ドキュメント検索
                                                    ↓
                                          グラフエッジ(SQL)保存
```

## 必要サービス

- **Mistral API**: 埋め込み (`mistral-embed`) + チャット (`mistral-large-latest`)
- **Qdrant**: ベクターDB（Docker で起動）
- **SQLite** (デフォルト) / PostgreSQL

## クイックスタート

```bash
# 1. 依存インストール
pip install -e ".[dev]"

# 2. 環境変数設定
cp .env.example .env
# → MISTRAL_API_KEY を記入

# 3. Qdrant 起動
docker run -p 6333:6333 qdrant/qdrant

# 4. DB初期化 & インデックス作成
python scripts/rebuild_index.py

# 5. API起動
uvicorn apps.api.main:app --reload

# 6. サンプルテキスト投入
python scripts/ingest_sample.py
```

## API エンドポイント

| Method | Path | 説明 |
|--------|------|------|
| POST | `/ingest` | テキスト投入 |
| GET | `/search?q=...` | セマンティック検索 |
| GET | `/related/{doc_id}` | 関連ドキュメント |
| POST | `/summarize` | クエリへの回答+要約 |
| CRUD | `/collections` | コレクション管理 |

## ディレクトリ構成

```
knowledge-organizer/
  apps/api/          FastAPI アプリ
  apps/worker/       非同期ワーカー（任意）
  core/              設定・ユーティリティ
  pipelines/         処理パイプライン
  storage/           SQL / Vector ストレージ
  prompts/           LLMプロンプト（Markdownテンプレート）
  scripts/           CLI スクリプト
  tests/             テスト
```
