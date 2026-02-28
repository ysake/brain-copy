#!/usr/bin/env python3
"""
日本語テキストの一覧から、可視化用のクラスタCSVを生成するスクリプト。

入力:
  - プレーンテキストファイル (UTF-8)
  - 1行 = 1ドキュメント（空行は無視）

処理:
  - Mistral の埋め込みAPIでテキストをベクトル化
  - KMeans でクラスタリング
  - 2次元座標: PCA または UMAP（--projection で指定。UMAP は似た意味を近く・違う意味を遠くに配置）

出力:
  - x,y,text,cluster のCSV
    → 生成されたCSVを index.html の「ファイルを選択」からアップロードするとマップに表示できる
"""

import argparse
import csv
import os
from typing import List

# .env から MISTRAL_API_KEY を読む（スクリプト同階層 or knowledge-organizer/.env）
try:
    from dotenv import load_dotenv
    _script_dir = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(_script_dir, ".env"))
    load_dotenv(os.path.join(_script_dir, "knowledge-organizer", ".env"))
    load_dotenv()  # カレントディレクトリの .env
except ImportError:
    pass

import numpy as np
from mistralai import Mistral
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
try:
    import umap
    HAS_UMAP = True
except ImportError:
    HAS_UMAP = False


def load_texts(path: str) -> List[str]:
    texts: List[str] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            texts.append(line)
    if not texts:
        raise ValueError(f"入力ファイル {path} に有効なテキスト行がありません。")
    return texts


def get_mistral_client() -> Mistral:
    api_key = os.getenv("MISTRAL_API_KEY")
    if not api_key:
        raise RuntimeError(
            "環境変数 MISTRAL_API_KEY が設定されていません。\n"
            "例: export MISTRAL_API_KEY='xxxxxxxx'"
        )
    return Mistral(api_key=api_key)


# Mistral の埋め込みAPIは1リクエストあたりの入力数に制限があるため、この件数で分割して送る
EMBED_BATCH_SIZE = 32


def embed_texts(client: Mistral, texts: List[str], model: str = "mistral-embed") -> np.ndarray:
    all_vectors = []
    for start in range(0, len(texts), EMBED_BATCH_SIZE):
        batch = texts[start : start + EMBED_BATCH_SIZE]
        resp = client.embeddings.create(model=model, inputs=batch)
        all_vectors.extend(item.embedding for item in resp.data)
    return np.asarray(all_vectors, dtype="float32")


def cluster_and_project(
    embeddings: np.ndarray,
    n_clusters: int,
    random_state: int = 42,
    projection: str = "umap",
) -> tuple[np.ndarray, np.ndarray]:
    # クラスタリング
    kmeans = KMeans(n_clusters=n_clusters, random_state=random_state, n_init=10)
    labels = kmeans.fit_predict(embeddings)

    n_samples = embeddings.shape[0]

    if projection == "umap" and HAS_UMAP and n_samples >= 3:
        # UMAP: 埋め込み空間で「近い＝似ている」を2次元でも保持 → 同じカテゴリは近く、違うカテゴリは遠く
        n_neighbors = min(15, max(2, n_samples - 1))
        reducer = umap.UMAP(
            n_components=2,
            n_neighbors=n_neighbors,
            min_dist=0.1,
            metric="cosine",
            random_state=random_state,
        )
        coords_2d = reducer.fit_transform(embeddings.astype(np.float64))
    else:
        # PCA: 分散が大きい2方向に射影（従来どおり）
        if projection == "umap" and (not HAS_UMAP or n_samples < 3):
            print("Warning: UMAP は未使用（umap未導入 or データが少ないため）。PCA で投影します。")
        pca = PCA(n_components=2, random_state=random_state)
        coords_2d = pca.fit_transform(embeddings)
    return coords_2d, labels


def get_distance_criterion_text(projection: str) -> str:
    """点同士の近さ・遠さの基準となる説明文を返す"""
    base = (
        "【点同士の近さ・遠さの基準】\n"
        "各テキストを Mistral の埋め込み API（mistral-embed）で「意味ベクトル」に変換し、\n"
        "そのベクトル同士の近さを元に座標を決めています。\n"
        "マップ上の距離が近い ＝ 意味が似ている、遠い ＝ 意味が違う、と解釈できます。\n\n"
        "【どういうロジックで「近い＝似ている」と判断しているか】\n"
        "・Mistral の埋め込みモデル（mistral-embed）が、テキストを 1024 次元のベクトルに変換します。\n"
        "・このモデルは学習データから「意味が近い文同士はベクトルも近くなる」ように訓練されています。\n"
        "・当スクリプトでは、そのベクトル同士の「ユークリッド距離」が小さいほど「近い」としています。\n"
        "・クラスタリング（KMeans）と2次元への投影（PCA/UMAP）も、このベクトル空間での距離を前提にしています。\n\n"
        "【何を重み付けしているか】\n"
        "・キーワードや語句をこちらで重み付けはしていません。\n"
        "・「どの語がどれだけ効くか」は、Mistral の埋め込みモデルが学習で獲得した内部パラメータで決まります。\n"
        "・同じ語でも文脈によって効き方が変わり、意味の近さとしてベクトルに反映されます。\n\n"
    )
    if projection == "umap":
        base += "2次元への投影: UMAP（埋め込み空間の近傍関係を2次元でも保持）。\n"
    else:
        base += "2次元への投影: PCA（分散が大きい2方向への射影）。\n"
    return base.strip()


def compute_connections(
    embeddings: np.ndarray,
    percentile: float = 30.0,
    top_k: int | None = None,
) -> tuple[List[List[int]], float, np.ndarray]:
    """
    埋め込み空間でペア間距離を計算し、接続を決める。
    top_k 指定時: 各ノードから類似度上位 top_k 件のみ接続（エッジ間引き）。
    否則: 距離が下位 percentile% のペアを接続。
    返す connected_to[i] は接続先インデックス j のリスト。
    """
    from sklearn.metrics.pairwise import euclidean_distances

    n = embeddings.shape[0]
    if n < 2:
        return [[] for _ in range(n)], 0.0, np.array([])

    dists = euclidean_distances(embeddings.astype(np.float64))

    connected_to: List[List[int]] = [[] for _ in range(n)]
    threshold = 0.0

    if top_k is not None and top_k > 0:
        # 各ノードから距離が近い順に top_k 件だけ接続（類似度上位N件）
        k_actual = min(top_k, n - 1)
        for i in range(n):
            # 自分以外の全ノードとの距離でソート（昇順）
            idx_dist = [(j, float(dists[i, j])) for j in range(n) if j != i]
            idx_dist.sort(key=lambda t: t[1])
            connected_to[i] = [j for j, _ in idx_dist[:k_actual]]
        # レポート用に閾値は「全ペアの中央」など適当に
        pair_distances = [dists[i, j] for i in range(n) for j in range(i + 1, n)]
        threshold = float(np.median(pair_distances)) if pair_distances else 0.0
    else:
        pair_distances = [dists[i, j] for i in range(n) for j in range(i + 1, n)]
        if not pair_distances:
            return connected_to, 0.0, dists
        threshold = float(np.percentile(pair_distances, percentile))
        for i in range(n):
            for j in range(i + 1, n):
                if dists[i, j] <= threshold:
                    connected_to[i].append(j)

    return connected_to, threshold, dists


def write_csv(
    path: str,
    coords_2d: np.ndarray,
    labels: np.ndarray,
    texts: List[str],
    connected_to: List[List[int]] | None = None,
) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if connected_to is not None:
            writer.writerow(["x", "y", "text", "cluster", "connected_to"])
            for idx, ((x, y), label, text) in enumerate(zip(coords_2d, labels, texts)):
                conn = ";".join(str(j) for j in connected_to[idx]) if connected_to else ""
                writer.writerow([f"{x:.6f}", f"{y:.6f}", text, int(label), conn])
        else:
            writer.writerow(["x", "y", "text", "cluster"])
            for (x, y), label, text in zip(coords_2d, labels, texts):
                writer.writerow([f"{x:.6f}", f"{y:.6f}", text, int(label)])


def write_criterion_file(output_csv_path: str, projection: str) -> None:
    """CSV と同じ場所に「距離の基準」説明テキストを書き出す"""
    base, _ = os.path.splitext(output_csv_path)
    path = base + "_距離の基準.txt"
    text = get_distance_criterion_text(projection)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"距離の基準の説明: {path}")


def write_connection_report(
    output_csv_path: str,
    texts: List[str],
    connected_to: List[List[int]],
    threshold: float,
    dists: np.ndarray,
    top_k: int | None = None,
) -> None:
    """接続されているかどうかの分析レポートを書き出す"""
    base, _ = os.path.splitext(output_csv_path)
    path = base + "_接続分析.txt"
    n = len(texts)
    if top_k is not None and top_k > 0:
        criterion_line = f"接続の基準: 各ノードから類似度（距離の近い順）上位 {top_k} 件のみエッジを張っています。"
    else:
        criterion_line = f"接続の基準: 埋め込み空間でのユークリッド距離が閾値以下（閾値 = {threshold:.4f}）のペアを接続。"
    lines = [
        "【接続分析】",
        criterion_line,
        "",
        "■ 接続されているペア（距離が近い＝意味が似ている）",
        "",
    ]
    connected_pairs = []
    for i in range(n):
        for j in connected_to[i]:
            connected_pairs.append((i, j, float(dists[i, j])))
    connected_pairs.sort(key=lambda t: t[2])
    for i, j, d in connected_pairs:
        ti = (texts[i][:40] + "…") if len(texts[i]) > 40 else texts[i]
        tj = (texts[j][:40] + "…") if len(texts[j]) > 40 else texts[j]
        lines.append(f"  [{i}]–[{j}] 距離={d:.4f}")
        lines.append(f"      [{i}] {ti}")
        lines.append(f"      [{j}] {tj}")
        lines.append("")

    lines.append("■ 接続されていないペア（距離が遠い＝意味が違う）")
    lines.append("")
    all_pairs = [(i, j, float(dists[i, j])) for i in range(n) for j in range(i + 1, n)]
    connected_set = {(min(i, j), max(i, j)) for i, j, _ in connected_pairs}
    disconnected = [(i, j, d) for i, j, d in all_pairs if (i, j) not in connected_set]
    disconnected.sort(key=lambda t: -t[2])  # 遠い順に最大10件
    for i, j, d in disconnected[:10]:
        ti = (texts[i][:35] + "…") if len(texts[i]) > 35 else texts[i]
        tj = (texts[j][:35] + "…") if len(texts[j]) > 35 else texts[j]
        lines.append(f"  [{i}]–[{j}] 距離={d:.4f}")
        lines.append(f"      [{i}] {ti}")
        lines.append(f"      [{j}] {tj}")
        lines.append("")
    if len(disconnected) > 10:
        lines.append(f"  … 他 {len(disconnected) - 10} ペアは非接続です。")
        lines.append("")

    lines.append("■ サマリ")
    lines.append(f"  接続ペア数: {len(connected_pairs)}")
    lines.append(f"  非接続ペア数: {len(disconnected)}")
    lines.append(f"  全ペア数: {len(all_pairs)}")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"接続分析レポート: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="日本語テキスト一覧から、クラスタ可視化用CSV (x,y,text,cluster) を生成します。"
    )
    parser.add_argument(
        "--input",
        "-i",
        required=True,
        help="入力テキストファイルのパス（1行=1ドキュメント, UTF-8）",
    )
    parser.add_argument(
        "--output",
        "-o",
        default="cluster_points.csv",
        help="出力CSVファイル名（デフォルト: cluster_points.csv）",
    )
    parser.add_argument(
        "--clusters",
        "-k",
        type=int,
        default=5,
        help="クラスタ数 (k)。index.html のデフォルト値と合わせるなら 3 〜 5 程度がおすすめ。",
    )
    parser.add_argument(
        "--projection",
        "-p",
        choices=["pca", "umap"],
        default="pca",
        help="2次元への投影方法。pca=分散の大きい2方向（デフォルト）。umap=似た意味を近くに（要: pip install umap-learn）。",
    )
    parser.add_argument(
        "--connection-percentile",
        type=float,
        default=30.0,
        help="接続とみなす距離のパーセンタイル（--top-edges 0 のときのみ）。下位この%%のペアを接続。",
    )
    parser.add_argument(
        "--top-edges",
        type=int,
        default=5,
        metavar="N",
        help="各ノードから類似度上位 N 件だけエッジを張る（デフォルト: 5）。0 にすると --connection-percentile を使用。",
    )

    args = parser.parse_args()

    texts = load_texts(args.input)
    print(f"Loaded {len(texts)} texts from {args.input}")

    client = get_mistral_client()
    print("Embedding texts with Mistral embeddings API...")
    embeddings = embed_texts(client, texts)
    print(f"Embeddings shape: {embeddings.shape}")

    print(f"Clustering into {args.clusters} clusters and projecting to 2D ({args.projection})...")
    coords_2d, labels = cluster_and_project(
        embeddings, n_clusters=args.clusters, projection=args.projection
    )

    if args.top_edges > 0:
        print(f"Computing connections (top-{args.top_edges} nearest per node)...")
        connected_to, conn_threshold, dists = compute_connections(
            embeddings, top_k=args.top_edges
        )
        print(f"  Each node connected to its {args.top_edges} nearest neighbors.")
    else:
        print("Computing connections (distance percentile)...")
        connected_to, conn_threshold, dists = compute_connections(
            embeddings, percentile=args.connection_percentile
        )
        print(f"  Connection threshold (percentile {args.connection_percentile}%): {conn_threshold:.4f}")

    write_csv(args.output, coords_2d, labels, texts, connected_to=connected_to)
    print(f"Saved clustered points to {args.output}")

    write_connection_report(
        args.output, texts, connected_to, conn_threshold, dists,
        top_k=args.top_edges if args.top_edges > 0 else None,
    )

    criterion_text = get_distance_criterion_text(args.projection)
    write_criterion_file(args.output, args.projection)
    print("\n" + criterion_text)
    print("\nこのCSVを index.html の『ファイルを選択』からアップロードするとマップに表示できます。")


if __name__ == "__main__":
    main()

