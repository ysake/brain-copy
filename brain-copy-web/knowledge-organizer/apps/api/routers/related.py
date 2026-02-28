"""GET /related/{doc_id} – 関連ドキュメント取得エンドポイント"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from apps.api.schemas.result import RelatedDoc, RelatedResponse
from apps.api.services.relate import get_related_documents
from storage.sql import repo
from storage.sql.repo import db_session

router = APIRouter(prefix="/related", tags=["related"])


@router.get("/{doc_id}", response_model=RelatedResponse)
def related(
    doc_id: str,
    top_k: int = Query(default=5, ge=1, le=20),
    session: Session = Depends(db_session),
):
    doc = repo.get_document(session, doc_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Document {doc_id} not found")

    related_raw = get_related_documents(doc_id=doc_id, session=session, top_k=top_k)
    related = [RelatedDoc(**r) for r in related_raw]
    return RelatedResponse(doc_id=doc_id, related=related)
