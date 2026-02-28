"""CRUD /collections – コレクション管理エンドポイント"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from apps.api.schemas.result import (
    CollectionAddDocRequest,
    CollectionCreateRequest,
    CollectionSchema,
)
from storage.sql import repo
from storage.sql.repo import db_session

router = APIRouter(prefix="/collections", tags=["collections"])


@router.get("", response_model=list[CollectionSchema])
def list_collections(session: Session = Depends(db_session)):
    cols = repo.list_collections(session)
    return [CollectionSchema(id=c.id, name=c.name, description=c.description, summary=c.summary) for c in cols]


@router.post("", response_model=CollectionSchema, status_code=201)
def create_collection(req: CollectionCreateRequest, session: Session = Depends(db_session)):
    existing = repo.get_collection_by_name(session, req.name)
    if existing:
        raise HTTPException(status_code=409, detail=f"Collection '{req.name}' already exists")
    col = repo.create_collection(session, name=req.name, description=req.description)
    return CollectionSchema(id=col.id, name=col.name, description=col.description, summary=col.summary)


@router.get("/{col_id}", response_model=CollectionSchema)
def get_collection(col_id: str, session: Session = Depends(db_session)):
    col = repo.get_collection(session, col_id)
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    return CollectionSchema(id=col.id, name=col.name, description=col.description, summary=col.summary)


@router.post("/{col_id}/documents", status_code=201)
def add_document_to_collection(
    col_id: str,
    req: CollectionAddDocRequest,
    session: Session = Depends(db_session),
):
    col = repo.get_collection(session, col_id)
    if col is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    doc = repo.get_document(session, req.document_id)
    if doc is None:
        raise HTTPException(status_code=404, detail="Document not found")
    repo.add_to_collection(session, col_id, req.document_id)
    return {"message": "Document added to collection"}
