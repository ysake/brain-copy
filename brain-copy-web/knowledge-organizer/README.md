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

# 5'. APIキーをコマンドから渡して起動（.env に書かなくてよい）
python scripts/run_api.py YOUR_MISTRAL_API_KEY
python scripts/run_api.py YOUR_MISTRAL_API_KEY --port 8001   # ポート指定

# または環境変数で渡す
MISTRAL_API_KEY=your_key uvicorn apps.api.main:app --reload

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
| POST | `/cluster/points-csv` | `texts` から `cluster_points.csv` 相当のCSVを返す |

### `POST /cluster/points-csv`

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
