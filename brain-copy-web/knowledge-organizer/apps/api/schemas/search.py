from pydantic import BaseModel, Field


class SearchRequest(BaseModel):
    q: str = Field(..., min_length=1, description="検索クエリ")
    top_k: int = Field(default=5, ge=1, le=50)
    score_threshold: float = Field(default=0.0, ge=0.0, le=1.0)


class SummarizeRequest(BaseModel):
    query: str = Field(..., min_length=1, description="質問・要約指示")
    top_k: int = Field(default=5, ge=1, le=20)
