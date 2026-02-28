"""簡易クラスタリング（KMeans）– 任意オプション"""
from __future__ import annotations

import numpy as np
from sklearn.cluster import KMeans
from sklearn.preprocessing import normalize


def cluster_vectors(
    vectors: list[list[float]],
    n_clusters: int = 5,
    random_state: int = 42,
) -> list[int]:
    """
    ベクターリストを KMeans でクラスタリングし、各ベクターのクラスタ番号を返す。

    Args:
        vectors: 埋め込みベクターのリスト
        n_clusters: クラスタ数（ドキュメント数より小さくなければならない）
        random_state: 再現性のための乱数シード

    Returns:
        labels: 各ベクターに対応するクラスタ番号のリスト
    """
    if len(vectors) <= 1:
        return [0] * len(vectors)

    n = min(n_clusters, len(vectors))
    arr = normalize(np.array(vectors, dtype=np.float32))
    km = KMeans(n_clusters=n, random_state=random_state, n_init="auto")
    labels = km.fit_predict(arr)
    return labels.tolist()


def group_by_cluster(
    items: list[dict],
    labels: list[int],
    id_key: str = "doc_id",
) -> dict[int, list[dict]]:
    """クラスタラベルでアイテムをグループ化する"""
    groups: dict[int, list[dict]] = {}
    for item, label in zip(items, labels):
        groups.setdefault(label, []).append(item)
    return groups
