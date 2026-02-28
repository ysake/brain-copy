from pydantic import BaseModel, Field


class ClusterPointsRequest(BaseModel):
    texts: list[str] = Field(..., min_length=2, description="クラスタ化対象テキスト（2件以上）")
    clusters: int = Field(default=5, ge=2, le=100, description="クラスタ数")
    top_edges: int = Field(default=5, ge=0, le=30, description="各ノードの近傍接続数。0で接続なし")
