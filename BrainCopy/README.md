# brain-copy

## English

### Specification (3D Network Graph / RealityKit)

#### Goal

Use RealityKit physics to place multiple spheres (nodes) in a zero-gravity space and represent a 3D network graph connected by rubber-band-like springs.

#### Visual Concept

- Multiple spheres float in zero gravity.
- Spheres repel each other, so unconnected nodes drift apart.
- Spheres connected by springs attract each other based on distance.
- The whole system converges to a balanced, spatially distributed network shape.

#### Core Concepts

- **Node**: Sphere (`ModelEntity` in RealityKit)
- **Edge**: Spring-like connection (physics constraint/force)
- **Space**: Zero gravity (gravity vector set to zero)
- **Dynamics**: Repulsion + spring attraction

#### Physics Spec (Phase 1)

- **Gravity**: None (`gravity = [0, 0, 0]`)
- **Repulsion**: Strong at close range and weakens beyond a threshold distance
- **Connection (Spring)**:
  - Has a rest length between two points
  - Repels when shorter than rest length, attracts when longer
  - Applies only to connected node pairs
- **Damping**: Apply damping so oscillation converges

#### Initial Conditions

- Number of nodes: 10-30 (to be parameterized later)
- Initial positions: Random around the origin
- Initial velocity: 0
- Number of edges: Random or predefined by node count (selection planned later)

#### Rendering / Screen Spec

- Render the 3D network in `RealityView`
- Display only in the first step (interaction later)
- Fixed viewpoint (gesture controls considered in future)

#### Implementation Approach (Draft)

- Use `RealityView` in `ContentView`
- Generate nodes as `ModelEntity`
- Implement dynamics in one of the following ways:
  - RealityKit rigid bodies + custom force application
  - Custom update loop that computes and applies positions

#### Future Extensions

- Node selection and drag interaction
- Edge visualization (line or cylinder)
- Node labels
- UI controls for physics parameters

### Data Input Format (Phase 2)

#### CSV

- Layout file: `BrainCopy/Resources/cluster_points.csv`
- Header: `x,y,text,cluster,connected_to`
- `connected_to` is a semicolon-separated node ID list (0-based row index)

#### JSON

```json
{
    "nodes": [
        { "id": 0, "x": 0.12, "y": -0.08, "z": 0.02, "label": "Sample", "cluster": 1 }
    ],
    "edges": [
        { "source": 0, "target": 1 }
    ]
}
```

### knowledge-organizer API Integration

Call the knowledge-organizer API (`/cluster/points-csv`) running on a Mac in the same LAN, then convert the returned CSV into the graph view.

#### Configuration (In App)

- API endpoint and parameters are currently hardcoded
- Planned to be editable from UI in Phase 5

#### Input Text

- Show FileImporter at launch and cluster the loaded text file
- Supported separators: newline or `|||`/`||`/`|`/`;`/`,`/tab
- If the loaded file is `.csv`, skip API call and treat it as API response CSV

#### Notes

- Start the API on a Mac in the same LAN and bind to `0.0.0.0`
- Because it is LAN communication, handle ATS exception settings as needed
- If communication fails, fall back to existing CSV (Bundle/Document)
- Show loading during request, and show error + retry path on failure

### Current Status

This project is a visionOS/AR application built with SwiftUI and RealityKit.

#### Current Behavior

- **Display**: A static blue sphere (radius 0.1m) is shown in `RealityView`
- **State variable**: `@State var enlarge` exists but is not connected to UI
- **Preview**: Uses volumetric window style
- **Removed**: `RealityKitContent` package has been removed

#### App Launch Flow

1. `ContentView` is shown by SwiftUI
2. A blue sphere is rendered in the `RealityView` container
3. No interaction features are implemented yet

#### File Structure

- `BrainCopy/BrainCopyApp.swift`: Main app entry point
- `BrainCopy/ContentView.swift`: Main view implementation
- `BrainCopyTests/BrainCopyTests.swift`: Test file

## 日本語

### 仕様（3Dネットワークグラフ / RealityKit）

#### 目的

RealityKitの物理演算を用いて、無重力空間に複数の球体（ノード）を配置し、ゴム紐（スプリング）で結ばれた3Dネットワークグラフを表現する。

#### 表現イメージ

- 無重力空間に複数の球体が浮遊
- 球体同士は反発力を持つため、結合がない場合は離れていく
- ゴム紐で接続された球体同士は、距離に応じて引き合う
- 全体としてバランスの取れた、広がりのあるネットワーク形状になる

#### 主要コンセプト

- **ノード**: 球体（RealityKit `ModelEntity`）
- **エッジ**: ゴム紐のようなスプリング（物理拘束 / 力）
- **空間**: 無重力（重力ベクトルはゼロ）
- **力学**: 反発 + 引力（スプリング）

#### 物理仕様（第一段階）

- **重力**: なし（`gravity = [0, 0, 0]`）
- **反発力**: 近距離で反発、一定距離を超えると影響が弱まる
- **結合（スプリング）**:
  - 2点間に自然長を持つ
  - 自然長より短いと反発、長いと引力
  - 結合があるノード同士のみ作用
- **ダンピング**: 振動が収束するように減衰を適用

#### 初期条件

- ノード数: 10〜30（後でパラメータ化）
- 初期位置: 原点付近にランダム配置
- 初期速度: 0
- エッジ数: ノード数に応じてランダム or 事前定義（後で選択可能）

#### 画面仕様

- `RealityView`内に3Dネットワークを表示
- まずは表示のみ（インタラクションは後回し）
- 視点は固定（将来的にジェスチャー操作を検討）

#### 実装方針（案）

- `ContentView`で`RealityView`を使用
- ノードは`ModelEntity`で生成
- 力学は以下のいずれかで実装
  - RealityKitの物理ボディ + カスタムフォース適用
  - 物理更新ループで独自計算し位置更新

#### 将来的な拡張

- ノードの選択・ドラッグ操作
- エッジの視覚化（ライン or シリンダー）
- ノードラベル表示
- 物理パラメータのUI調整

### データ入力フォーマット（Phase 2）

#### CSV

- 配置ファイル: `BrainCopy/Resources/cluster_points.csv`
- ヘッダ: `x,y,text,cluster,connected_to`
- `connected_to` はセミコロン区切りのノードID（0始まりの行番号）

#### JSON

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

### knowledge-organizer API 連携

同一LAN上のMacで動く knowledge-organizer のAPI（`/cluster/points-csv`）を呼び出し、返ってきたCSVをグラフ表示に変換します。

#### 設定（アプリ内）

- APIの接続先とパラメータはコード内に埋め込み済み
- Phase 5 でUIから編集できるようにする予定

#### 入力テキスト

- 起動時に FileImporter を表示し、テキストファイルを読み込んでクラスタリングします。
- テキストファイルは改行区切り or `|||`/`||`/`|`/`;`/`,`/タブ区切りに対応します。
- 読み込んだファイルが `.csv` の場合は API を呼ばず、CSVをAPIレスポンスとして扱います。

#### 注意事項

- APIは同一LAN上のMacで起動し、`0.0.0.0` バインドでアクセスできるようにします。
- LAN内通信のため、必要に応じてATS例外の扱いを検討します。
- 通信に失敗した場合は、既存CSV（Bundle/Document）にフォールバックします。
- APIリクエスト中はローディング表示を出し、失敗時はエラーとリトライ導線を表示します。

### 現在の状況

このプロジェクトはSwiftUIとRealityKitを使用したvisionOS/ARアプリケーションです。

#### 現在の挙動

- **表示内容**: RealityView内に青色の球体（半径0.1m）が静的に表示されます
- **状態変数**: `@State var enlarge`変数が存在しますが、UIと接続されておらず機能していません
- **プレビュー**: volumetricウィンドウスタイルを使用
- **削除済み**: RealityKitContentパッケージは削除されています

#### アプリ起動時の流れ

1. SwiftUIの`ContentView`が表示されます
2. `RealityView`コンテナ内に青色の球体がレンダリングされます
3. 現在、インタラクション機能は実装されていません

#### ファイル構成

- `BrainCopy/BrainCopyApp.swift`: メインのアプリエントリポイント
- `BrainCopy/ContentView.swift`: メインビューの実装
- `BrainCopyTests/BrainCopyTests.swift`: テストファイル
