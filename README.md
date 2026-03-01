# brain-copy

## English

### Overview

`brain-copy` is a monorepo for building and visualizing text knowledge graphs across visionOS and web environments.

- `BrainCopy`: visionOS app (SwiftUI + RealityKit) for 3D graph visualization
- `brain-copy-web`: web tools and scripts for text clustering and visualization
- `knowledge-organizer`: FastAPI backend for ingesting text, generating embeddings, and creating cluster CSV data

### Projects

- [BrainCopy (visionOS app)](./BrainCopy/README.md)
- [brain-copy-web (web tools)](./brain-copy-web/README.md)
- [knowledge-organizer (API backend)](./brain-copy-web/knowledge-organizer/README.md)

### Repository Structure

```text
brain-copy/
├── BrainCopy/                         # visionOS app source
├── BrainCopy.xcodeproj/              # Xcode project
├── BrainCopyTests/                   # App tests
└── brain-copy-web/                   # Web + backend related projects
    └── knowledge-organizer/          # FastAPI + vector/search pipeline
```

---

## 日本語

### 概要

`brain-copy` は、visionOS と Web の両環境でテキスト知識グラフを生成・可視化するためのモノレポです。

- `BrainCopy`: 3Dグラフ可視化用の visionOS アプリ（SwiftUI + RealityKit）
- `brain-copy-web`: テキストのクラスタリングと可視化を行う Web ツール群
- `knowledge-organizer`: テキスト投入、埋め込み生成、クラスタCSV生成を行う FastAPI バックエンド

### プロジェクト一覧

- [BrainCopy (visionOSアプリ)](./BrainCopy/README.md)
- [brain-copy-web (Webツール)](./brain-copy-web/README.md)
- [knowledge-organizer (APIバックエンド)](./brain-copy-web/knowledge-organizer/README.md)

### リポジトリ構成

```text
brain-copy/
├── BrainCopy/                         # visionOS アプリ本体
├── BrainCopy.xcodeproj/              # Xcode プロジェクト
├── BrainCopyTests/                   # アプリテスト
└── brain-copy-web/                   # Web + バックエンド関連
    └── knowledge-organizer/          # FastAPI + ベクター検索パイプライン
```
