# BrainCopy visionOS 移植計画

## 目的
- 既存の `BrainCopy/BrainCopy` をベースに、visionOS 向けの3Dネットワーク可視化アプリとして完成度を高める。
- まずはローカルで動く3Dネットワーク（ノード+エッジ+物理）を安定動作させ、次にデータ連携と操作性を拡張する。

## 現状整理（ベース実装）
- `ContentView.swift` で RealityView 内にノード・エッジ・簡易物理（反発+スプリング）を実装済み。
- ノード数、パラメータは固定。データ入力やUI操作は未実装。
- `BrainCopyApp.swift` で `.volumetric` ウィンドウの基本起動は完了。

## ゴール定義（MVP → 拡張）
### MVP
- 安定した3Dネットワーク描画（30〜200ノード規模での挙動）
- ノード/エッジの見た目が破綻しない
- 視点固定のままでも閲覧性が確保できる

### 拡張
- データ連携（CSV / API / ローカルJSON）
- ノード選択・ラベル表示・ホバー情報
- スケール/位置調整 UI、物理パラメータ調整 UI
- 入力テキスト → クラスタリング結果の反映

## 主要課題
- 物理挙動の安定性（ノード数増加での発散・振動）
- 表示性能（RealityKit + D3風グラフの3D変換）
- データ入出力（CSV / API）と3D描画の橋渡し

## 移植/実装計画

### Phase 0: ベース確認
- ゴール: 既存の3Dネットワークが安定して描画され、60fps近い挙動で継続動作する
- 進捗管理用ドキュメントを追加（`progress_tracking.md`）
- 既存 `ContentView.swift` の挙動を検証
- 物理パラメータのチューニング（発散しない範囲）
- ノード数を増やして性能ボトルネックを特定

### Phase 1: 3D表示の基盤強化
- ゴール: 200ノード規模で描画・更新が破綻せず、描画責務が整理されている
- ノード・エッジ描画の責務分離（Renderer / Simulation）
- Edge描画の最適化（メッシュ再生成せずTransformのみ更新）
- ノード半径・色のスケーリング対応（次数・クラスタ等）

### Phase 2: データレイヤの導入
- ゴール: CSV/JSONから読み込んだデータでネットワークを再構成できる
- 入力フォーマット定義（CSV/JSON）
- ローカル読み込み（Bundle/Document）
- `Node` / `Edge` のデータモデル追加
- 既存 `NetworkGraphSimulation` を入力データで初期化

### Phase 3: UIとインタラクション
- ゴール: 基本操作（選択・ラベル・調整UI）が実用レベルで動作する
- ノード選択（タップ・視線・ポインタ）
- ノードラベルの表示
- パラメータ調整 UI（SwiftUI side panel）
- カメラ or 視点調整（必要なら）

#### 補足（データソース）
- Phase 3 までは `brain-copy-web/cluster_points.csv` を読み込んでグラフ表示する想定

### Phase 4: knowledge-organizer 機能のアプリ内実装
- ゴール: Mistral APIとローカルベクトル検索で、検索/要約/関連が一通り動作する
- Python/FastAPIは使わず、SwiftでMistral APIを直接呼び出す
- `brain-copy-web/texts.txt` から、埋め込み・クラスタリング・投影・接続生成をアプリ内で実行
- `/ingest`, `/search`, `/related`, `/summarize` 相当の処理をアプリ内で再構成
- 応答を `Node`/`Edge` に変換し、グラフへ反映
- データ更新時のアニメーション/トランジション

#### Phase 4 追加設計: Mistral API（Swift）
- クライアント: `URLSession` + `async/await` の薄いラッパー
- 認証: APIキーをKeychainに保存（初回入力UI or 設定画面）
- モデル: 埋め込み用と要約/回答用で用途別に分離（モデル名は実装時に最新ドキュメントで確認）
- 主要処理:
  - インジェスト: テキスト→チャンク化→埋め込み→ローカル保存
  - 検索: クエリ埋め込み→類似検索（ローカルベクトル）
  - 関連: 上位類似のエッジ生成→グラフ更新
  - 要約: 上位関連テキストをコンテキストに要約/回答
- エラーハンドリング: リトライ（指数バックオフ）、タイムアウト、オフライン時の結果キャッシュ
- レート制御: 同時リクエスト数制限 + バッチ化

### Phase 5: 自由なテキストファイル入力
- ゴール: 任意のテキストファイルを読み込み、アプリ内でグラフ生成できる
- Documents/Files からのファイル読み込み（FileImporter）
- 文字コード判定（UTF-8前提、失敗時のガイド）
- 複数フォーマット対応（1行=1テキスト or 区切り記号）
- 大きなファイルの段階処理（分割・進捗表示）

## 技術方針
- SwiftUI + RealityKit を維持
- web版（D3 forceSimulation）相当の「ゴムの伸び縮み」は、visionOS ではCPU側の自前力学計算で再現する
- シミュレーションはCPU側で独自計算継続（現状踏襲）
- `RealityView` 更新ループでステップ
- データモデルは `struct Node`, `struct Edge` を導入し、描画・物理に渡す

### RealityKitの物理演算を利用しない理由
- グラフ特有の「反発 + スプリング + 減衰」の制御を細かく調整したい
- データ駆動の重み付け（次数・クラスタ・類似度）を力学に直接反映したい
- ノード数や更新頻度を制御し、描画・計算コストを最適化したい
- 既存の自前実装をベースに段階的に拡張できる

## 成果物
- visionOS ネイティブアプリ（`BrainCopy/BrainCopy`）
- 3Dネットワーク描画・インタラクション・データ連携
- 移植後の設計ドキュメント・API仕様書（必要なら追加）

## マイルストーン案
- M1: 物理安定化とノード数スケーリング
- M2: データ入力（CSV/JSON）対応
- M3: 基本UIと選択インタラクション
- M4: knowledge-organizer 機能のアプリ内実装（Swift + Mistral API）
- M5: 自由なテキストファイル入力（FileImporter + 大規模処理対応）

## リスクと対策
- 物理挙動が不安定 → ステップ間隔の固定化/クランプ、減衰強化
- ノード数増でフレーム落ち → 描画・更新を間引き、LOD導入
- データサイズが大きい → 段階的ロード/クラスタ単位の表示
- Mistral APIの認証/通信エラー → リトライ・タイムアウト・オフライン時のフォールバック

## Mistral API 実装詳細（Swift）

### エンドポイント設計（方針）
- 埋め込み: `embeddings` API を使用（入力: 文字列 or 文字列配列）
- 要約/回答: `chat/completions` API を使用（入力: messages）
- 具体的なURL/モデル名/リクエスト形式は実装時に最新ドキュメントで確定

### Swift での最小クライアント構成
- `MistralClient`（URLSession + async/await）
- `MistralRequestBuilder`（ヘッダ/JSON整形）
- `MistralResponseDecoder`（Codableでパース）

### 推奨データモデル（概略）
- `EmbeddingRequest`: `model`, `input`
- `EmbeddingResponse`: `data`（各要素に `embedding`）
- `ChatRequest`: `model`, `messages`, `temperature`, `maxTokens`
- `ChatResponse`: `choices`（`message` 内に `content`）
- 具体的なキーは仕様確定後に確実に合わせる（ここでは型の置き場だけ決める）

### 処理フロー（Swift内）
- ingest: `TextChunker` → `EmbeddingService` → `LocalVectorIndex` へ保存
- search: `EmbeddingService` → `LocalVectorIndex.search` → 上位kを取得
- related: `GraphBuilder` が上位類似をエッジ化
- summarize: `ChatService` に関連テキストを投入して要約/回答

### セキュリティ/運用
- APIキーはDocuments直下の設定ファイルから読み込む（Fileアプリ経由で配置/更新）
- `Info.plist` にファイル共有/ファイルアプリ経由のアクセス許可を追加
- 通信はATS準拠のHTTPSのみ
- 失敗時はローカルキャッシュ結果を返す

## 次のアクション（おすすめ順）
1. ノード数を 16 → 64/128 に増やして安定性テスト
2. `Node`/`Edge` データモデルの導入
3. CSV読み込み or JSON読み込みの簡易実装
