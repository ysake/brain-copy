# brain-copy

## 仕様（3Dネットワークグラフ / RealityKit）

### 目的

RealityKitの物理演算を用いて、無重力空間に複数の球体（ノード）を配置し、ゴム紐（スプリング）で結ばれた3Dネットワークグラフを表現する。

### 表現イメージ

- 無重力空間に複数の球体が浮遊
- 球体同士は反発力を持つため、結合がない場合は離れていく
- ゴム紐で接続された球体同士は、距離に応じて引き合う
- 全体としてバランスの取れた、広がりのあるネットワーク形状になる

### 主要コンセプト

- **ノード**: 球体（RealityKit `ModelEntity`）
- **エッジ**: ゴム紐のようなスプリング（物理拘束 / 力）
- **空間**: 無重力（重力ベクトルはゼロ）
- **力学**: 反発 + 引力（スプリング）

### 物理仕様（第一段階）

- **重力**: なし（`gravity = [0, 0, 0]`）
- **反発力**: 近距離で反発、一定距離を超えると影響が弱まる
- **結合（スプリング）**:
  - 2点間に自然長を持つ
  - 自然長より短いと反発、長いと引力
  - 結合があるノード同士のみ作用
- **ダンピング**: 振動が収束するように減衰を適用

### 初期条件

- ノード数: 10〜30（後でパラメータ化）
- 初期位置: 原点付近にランダム配置
- 初期速度: 0
- エッジ数: ノード数に応じてランダム or 事前定義（後で選択可能）

### 画面仕様

- `RealityView`内に3Dネットワークを表示
- まずは表示のみ（インタラクションは後回し）
- 視点は固定（将来的にジェスチャー操作を検討）

### 実装方針（案）

- `ContentView`で`RealityView`を使用
- ノードは`ModelEntity`で生成
- 力学は以下のいずれかで実装
  - RealityKitの物理ボディ + カスタムフォース適用
  - 物理更新ループで独自計算し位置更新

### 将来的な拡張

- ノードの選択・ドラッグ操作
- エッジの視覚化（ライン or シリンダー）
- ノードラベル表示
- 物理パラメータのUI調整

## データ入力フォーマット（Phase 2）

### CSV

- 配置ファイル: `BrainCopy/Resources/cluster_points.csv`
- ヘッダ: `x,y,text,cluster,connected_to`
- `connected_to` はセミコロン区切りのノードID（0始まりの行番号）

### JSON

```json
{
    "nodes": [
        { "id": 0, "x": 0.12, "y": -0.08, "z": 0.02, "label": "サンプル", "cluster": 1 }
    ],
    "edges": [
        { "source": 0, "target": 1 }
    ]
}
```

## knowledge-organizer API 連携

同一LAN上のMacで動く knowledge-organizer のAPI（`/cluster/points-csv`）を呼び出し、返ってきたCSVをグラフ表示に変換します。

### 設定ファイル（Documents）

- ファイル名: `BrainCopyConfig.json`
- 配置場所: `~/Documents/BrainCopyConfig.json`
- 例:

```json
{
    "apiBaseURL": "http://192.168.0.10:8000",
    "clusters": 5,
    "topEdges": 5,
}
```

### 入力テキスト

- Phase 5 ではアプリに組み込みのテキストを使用します。
- Phase 6 で FileImporter によるファイル選択を追加します。

### 注意事項

- APIは同一LAN上のMacで起動し、`0.0.0.0` バインドでアクセスできるようにします。
- LAN内通信のため、必要に応じてATS例外の扱いを検討します。
- 通信に失敗した場合は、既存CSV（Bundle/Document）にフォールバックします。
- APIリクエスト中はローディング表示を出し、失敗時はエラーとリトライ導線を表示します。

## 現在の状況

このプロジェクトはSwiftUIとRealityKitを使用したvisionOS/ARアプリケーションです。

### 現在の挙動

- **表示内容**: RealityView内に青色の球体（半径0.1m）が静的に表示されます
- **状態変数**: `@State var enlarge`変数が存在しますが、UIと接続されておらず機能していません
- **プレビュー**: volumetricウィンドウスタイルを使用
- **削除済み**: RealityKitContentパッケージは削除されています

### アプリ起動時の流れ

1. SwiftUIの`ContentView`が表示されます
2. `RealityView`コンテナ内に青色の球体がレンダリングされます
3. 現在、インタラクション機能は実装されていません

### ファイル構成

- `BrainCopy/BrainCopyApp.swift`: メインのアプリエントリポイント
- `BrainCopy/ContentView.swift`: メインビューの実装
- `BrainCopyTests/BrainCopyTests.swift`: テストファイル
