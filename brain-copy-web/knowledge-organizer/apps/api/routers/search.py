"""GET /search – セマンティック検索エンドポイント"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from apps.api.schemas.result import SearchHit, SearchResponse
from apps.api.services.retrieval import semantic_search
from storage.sql.repo import db_session

router = APIRouter(prefix="/search", tags=["search"])


@router.get("", response_model=SearchResponse)
def search(
    q: str = Query(..., min_length=1, description="検索クエリ"),
    top_k: int = Query(default=5, ge=1, le=50),
    score_threshold: float = Query(default=0.0, ge=0.0, le=1.0),
    session: Session = Depends(db_session),
):
    hits_raw = semantic_search(
        query=q,
        session=session,
        top_k=top_k,
        score_threshold=score_threshold if score_threshold > 0 else None,
    )
    hits = [SearchHit(**h) for h in hits_raw]
    return SearchResponse(query=q, hits=hits, total=len(hits))
