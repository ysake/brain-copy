"""POST /cluster/points-csv – texts から cluster_points.csv を生成"""
import csv
from io import StringIO

import numpy as np
from fastapi import APIRouter, HTTPException
from fastapi.responses import PlainTextResponse
from sklearn.decomposition import PCA
from sklearn.metrics.pairwise import euclidean_distances

from apps.api.schemas.cluster import ClusterPointsRequest
from pipelines.enrich.embedder import embed_texts
from pipelines.relate.cluster import cluster_vectors

router = APIRouter(prefix="/cluster", tags=["cluster"])


def _project_to_2d(vectors: list[list[float]]) -> np.ndarray:
    arr = np.asarray(vectors, dtype=np.float32)
    pca = PCA(n_components=2, random_state=42)
    return pca.fit_transform(arr)


def _build_connections(vectors: list[list[float]], top_edges: int) -> list[list[int]]:
    arr = np.asarray(vectors, dtype=np.float64)
    n = arr.shape[0]
    connected_to: list[list[int]] = [[] for _ in range(n)]
    if top_edges <= 0 or n <= 1:
        return connected_to

    dists = euclidean_distances(arr)
    k_actual = min(top_edges, n - 1)
    for i in range(n):
        idx_dist = [(j, float(dists[i, j])) for j in range(n) if j != i]
        idx_dist.sort(key=lambda t: t[1])
        connected_to[i] = [j for j, _ in idx_dist[:k_actual]]
    return connected_to


@router.post("/points-csv", response_class=PlainTextResponse)
def cluster_points_csv(req: ClusterPointsRequest):
    texts = [t.strip() for t in req.texts if t and t.strip()]
    if len(texts) < 2:
        raise HTTPException(status_code=422, detail="texts は2件以上必要です。")

    try:
        vectors = embed_texts(texts)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"埋め込み生成に失敗: {exc}") from exc

    labels = cluster_vectors(vectors, n_clusters=req.clusters)
    coords_2d = _project_to_2d(vectors)
    connected_to = _build_connections(vectors, req.top_edges)

    output = StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["x", "y", "text", "cluster", "connected_to"])
    for idx, ((x, y), label, text) in enumerate(zip(coords_2d, labels, texts)):
        conn = ";".join(str(j) for j in connected_to[idx])
        writer.writerow([f"{x:.6f}", f"{y:.6f}", text, int(label), conn])

    return PlainTextResponse(
        output.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": "attachment; filename=cluster_points.csv"},
    )
