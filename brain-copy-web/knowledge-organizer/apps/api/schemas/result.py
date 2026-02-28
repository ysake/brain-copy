from pydantic import BaseModel


class SearchHit(BaseModel):
    score: float
    chunk_id: str
    chunk_text: str
    doc_id: str
    doc_title: str
    doc_source: str | None


class SearchResponse(BaseModel):
    query: str
    hits: list[SearchHit]
    total: int


class RelatedDoc(BaseModel):
    doc_id: str
    title: str
    score: float
    relation_type: str


class RelatedResponse(BaseModel):
    doc_id: str
    related: list[RelatedDoc]


class SummarizeResponse(BaseModel):
    query: str
    answer: str
    sources: list[SearchHit]


class CollectionSchema(BaseModel):
    id: str
    name: str
    description: str | None
    summary: str | None


class CollectionCreateRequest(BaseModel):
    name: str
    description: str | None = None


class CollectionAddDocRequest(BaseModel):
    document_id: str
