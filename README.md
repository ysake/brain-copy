# brain-copy

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