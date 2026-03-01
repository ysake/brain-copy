# knowledge-organizer

## English

Minimal knowledge organizer pipeline: ingest text -> build relations -> summarize (assuming Mistral API)

### Architecture

```
Text ingestion -> Chunking -> Mistral embedding -> Qdrant storage
                                                   ↓
                              Tagging (LLM) <- Text summarization (LLM)
                                                   ↓
                                      Related document retrieval
                                                   ↓
                                      Graph edge (SQL) persistence
```

### Required Services

- **Mistral API**: Embeddings (`mistral-embed`) + chat (`mistral-large-latest`)
- **Qdrant**: Vector DB (typically launched with Docker)
- **SQLite** (default) / PostgreSQL

### Quick Start

```bash
# 1. Install dependencies
pip install -e ".[dev]"

# 2. Configure environment variables
cp .env.example .env
# -> Set MISTRAL_API_KEY

# 3. Start Qdrant
docker run -p 6333:6333 qdrant/qdrant

# 4. Initialize DB & create indexes
python scripts/rebuild_index.py

# 5. Start API
uvicorn apps.api.main:app --reload

# 5'. Start API by passing API key directly (no need to write .env)
python scripts/run_api.py YOUR_MISTRAL_API_KEY
python scripts/run_api.py YOUR_MISTRAL_API_KEY --port 8001   # specify port

# Or pass via environment variable
MISTRAL_API_KEY=your_key uvicorn apps.api.main:app --reload

# 6. Ingest sample text
python scripts/ingest_sample.py
```

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/ingest` | Ingest text |
| GET | `/search?q=...` | Semantic search |
| GET | `/related/{doc_id}` | Related documents |
| POST | `/summarize` | Answer + summary for a query |
| CRUD | `/collections` | Collection management |
| POST | `/cluster/points-csv` | Returns a CSV equivalent to `cluster_points.csv` from `texts` |

#### `POST /cluster/points-csv`

Returns `text/csv` with columns: `x,y,text,cluster,connected_to`.

- Request example:

```json
{
  "texts": ["Text A", "Text B", "Text C"],
  "clusters": 5,
  "top_edges": 5
}
```

- Parameters:
  - `texts` (required): array of at least 2 text items
  - `clusters` (optional): number of clusters (default: `5`)
  - `top_edges` (optional): neighbor connection count per point; `0` disables connections (default: `5`)

- `curl` example:

```bash
curl -X POST http://127.0.0.1:8000/cluster/points-csv \
  -H "Content-Type: application/json" \
  -d '{"texts":["A dog runs in a park.","A cat sleeps in the sun.","The stock market went up."],"clusters":2,"top_edges":2}'
```

### Usage from visionOS

When calling from another device such as Vision Pro, start the API bound to `0.0.0.0` and access it via the host Mac's LAN IP.

```bash
QDRANT_PATH=./.qdrant .venv/bin/python -m uvicorn apps.api.main:app --host 0.0.0.0 --port 8000
```

visionOS (Swift) example:

```swift
import Foundation

struct ClusterRequest: Encodable {
    let texts: [String]
    let clusters: Int
    let top_edges: Int
}

func fetchClusterCSV() async throws -> String {
    let url = URL(string: "http://192.168.0.10:8000/cluster/points-csv")! // Replace with Mac LAN IP
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
        ClusterRequest(
            texts: ["A dog runs in a park.", "A cat sleeps in the sun.", "The stock market went up."],
            clusters: 2,
            top_edges: 2
        )
    )

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    guard let csv = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeRawData)
    }
    return csv
}
```

### Directory Layout

```
knowledge-organizer/
  apps/api/          FastAPI app
  apps/worker/       Async worker (optional)
  core/              Config and utilities
  pipelines/         Processing pipelines
  storage/           SQL / vector storage
  prompts/           LLM prompts (Markdown templates)
  scripts/           CLI scripts
  tests/             Tests
```

## 日本語

テキスト投入 → 関連づけ → まとめ の最小構成ナレッジオーガナイザー（Mistral API前提）

### アーキテクチャ

```
テキスト投入 → チャンク分割 → Mistral埋め込み → Qdrant保存
                                                    ↓
                              タグ付け(LLM) ← テキスト要約(LLM)
                                                    ↓
                                            関連ドキュメント検索
                                                    ↓
                                          グラフエッジ(SQL)保存
```

### 必要サービス

- **Mistral API**: 埋め込み (`mistral-embed`) + チャット (`mistral-large-latest`)
- **Qdrant**: ベクターDB（Docker で起動）
- **SQLite** (デフォルト) / PostgreSQL

### クイックスタート

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

# 5'. APIキーをコマンドから渡して起動（.env に書かなくてよい）
python scripts/run_api.py YOUR_MISTRAL_API_KEY
python scripts/run_api.py YOUR_MISTRAL_API_KEY --port 8001   # ポート指定

# または環境変数で渡す
MISTRAL_API_KEY=your_key uvicorn apps.api.main:app --reload

# 6. サンプルテキスト投入
python scripts/ingest_sample.py
```

### API エンドポイント

| Method | Path | 説明 |
|--------|------|------|
| POST | `/ingest` | テキスト投入 |
| GET | `/search?q=...` | セマンティック検索 |
| GET | `/related/{doc_id}` | 関連ドキュメント |
| POST | `/summarize` | クエリへの回答+要約 |
| CRUD | `/collections` | コレクション管理 |
| POST | `/cluster/points-csv` | `texts` から `cluster_points.csv` 相当のCSVを返す |

#### `POST /cluster/points-csv`

`text/csv` をレスポンスとして返します。返却列は `x,y,text,cluster,connected_to` です。

- リクエスト例:

```json
{
  "texts": ["テキストA", "テキストB", "テキストC"],
  "clusters": 5,
  "top_edges": 5
}
```

- パラメータ:
  - `texts` (必須): 2件以上のテキスト配列
  - `clusters` (任意): クラスタ数（デフォルト: `5`）
  - `top_edges` (任意): 各点の近傍接続数。`0` で接続なし（デフォルト: `5`）

- `curl` 実行例:

```bash
curl -X POST http://127.0.0.1:8000/cluster/points-csv \
  -H "Content-Type: application/json" \
  -d '{"texts":["犬が公園を走る。","猫が日なたで寝る。","株式市場が上昇した。"],"clusters":2,"top_edges":2}'
```

### visionOS からの利用例

Vision Pro など別デバイスから呼ぶ場合は、API を `0.0.0.0` バインドで起動し、同一LAN上のMacのIPでアクセスします。

```bash
QDRANT_PATH=./.qdrant .venv/bin/python -m uvicorn apps.api.main:app --host 0.0.0.0 --port 8000
```

visionOS（Swift）例:

```swift
import Foundation

struct ClusterRequest: Encodable {
    let texts: [String]
    let clusters: Int
    let top_edges: Int
}

func fetchClusterCSV() async throws -> String {
    let url = URL(string: "http://192.168.0.10:8000/cluster/points-csv")! // Mac の LAN IP に置換
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
        ClusterRequest(
            texts: ["犬が公園を走る。", "猫が日なたで寝る。", "株式市場が上昇した。"],
            clusters: 2,
            top_edges: 2
        )
    )

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    guard let csv = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeRawData)
    }
    return csv
}
```

### ディレクトリ構成

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
