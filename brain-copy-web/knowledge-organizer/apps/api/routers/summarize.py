"""POST /summarize – RAGスタイルの回答生成エンドポイント"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from apps.api.schemas.result import SearchHit, SummarizeResponse
from apps.api.schemas.search import SummarizeRequest
from apps.api.services.retrieval import semantic_search
from apps.api.services.summarizer import answer_with_context
from storage.sql.repo import db_session

router = APIRouter(prefix="/summarize", tags=["summarize"])


@router.post("", response_model=SummarizeResponse)
def summarize(req: SummarizeRequest, session: Session = Depends(db_session)):
    # 1. 関連チャンクを検索
    hits_raw = semantic_search(
        query=req.query,
        session=session,
        top_k=req.top_k,
    )

    # 2. LLM で回答生成
    answer = answer_with_context(query=req.query, context_chunks=hits_raw)

    hits = [SearchHit(**h) for h in hits_raw]
    return SummarizeResponse(query=req.query, answer=answer, sources=hits)
