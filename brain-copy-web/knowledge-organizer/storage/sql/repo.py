"""SQLAlchemy リポジトリ – CRUD 操作をまとめる"""
from collections.abc import Generator
from contextlib import contextmanager
from typing import Any

from sqlalchemy import create_engine, select, delete
from sqlalchemy.orm import Session, sessionmaker

from core.config import get_settings
from storage.sql.models import Base, Chunk, Collection, CollectionMember, Document, Edge

settings = get_settings()

_engine = create_engine(
    settings.database_url,
    connect_args={"check_same_thread": False} if "sqlite" in settings.database_url else {},
)
_SessionLocal = sessionmaker(bind=_engine, expire_on_commit=False)


def init_db() -> None:
    """テーブルを作成する（初回起動 or rebuild_index 用）"""
    Base.metadata.create_all(_engine)


@contextmanager
def get_session() -> Generator[Session, None, None]:
    session = _SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


# FastAPI の Depends 用
def db_session() -> Generator[Session, None, None]:
    with get_session() as session:
        yield session


# ── Document ─────────────────────────────────────────────────────────────────

def upsert_document(session: Session, **kwargs: Any) -> Document:
    """content_hash が既存なら返し、なければ作成"""
    stmt = select(Document).where(Document.content_hash == kwargs["content_hash"])
    existing = session.scalars(stmt).first()
    if existing:
        return existing
    doc = Document(**kwargs)
    session.add(doc)
    session.flush()
    return doc


def get_document(session: Session, doc_id: str) -> Document | None:
    return session.get(Document, doc_id)


def list_documents(session: Session, limit: int = 100, offset: int = 0) -> list[Document]:
    return list(session.scalars(select(Document).offset(offset).limit(limit)))


def delete_document(session: Session, doc_id: str) -> bool:
    doc = session.get(Document, doc_id)
    if doc is None:
        return False
    session.delete(doc)
    return True


# ── Chunk ─────────────────────────────────────────────────────────────────────

def bulk_insert_chunks(session: Session, chunks: list[dict]) -> list[Chunk]:
    objs = [Chunk(**c) for c in chunks]
    session.add_all(objs)
    session.flush()
    return objs


def get_chunks_by_doc(session: Session, doc_id: str) -> list[Chunk]:
    return list(session.scalars(select(Chunk).where(Chunk.document_id == doc_id)))


def get_chunk_by_vector_id(session: Session, vector_id: str) -> Chunk | None:
    return session.scalars(select(Chunk).where(Chunk.vector_id == vector_id)).first()


# ── Collection ────────────────────────────────────────────────────────────────

def create_collection(session: Session, name: str, description: str | None = None) -> Collection:
    col = Collection(name=name, description=description)
    session.add(col)
    session.flush()
    return col


def get_collection(session: Session, col_id: str) -> Collection | None:
    return session.get(Collection, col_id)


def get_collection_by_name(session: Session, name: str) -> Collection | None:
    return session.scalars(select(Collection).where(Collection.name == name)).first()


def list_collections(session: Session) -> list[Collection]:
    return list(session.scalars(select(Collection)))


def add_to_collection(session: Session, collection_id: str, document_id: str) -> CollectionMember:
    member = CollectionMember(collection_id=collection_id, document_id=document_id)
    session.add(member)
    session.flush()
    return member


# ── Edge ──────────────────────────────────────────────────────────────────────

def upsert_edge(
    session: Session,
    source_doc_id: str,
    target_doc_id: str,
    score: float,
    relation_type: str = "similar",
) -> Edge:
    stmt = select(Edge).where(
        Edge.source_doc_id == source_doc_id,
        Edge.target_doc_id == target_doc_id,
        Edge.relation_type == relation_type,
    )
    existing = session.scalars(stmt).first()
    if existing:
        existing.score = score
        return existing
    edge = Edge(
        source_doc_id=source_doc_id,
        target_doc_id=target_doc_id,
        score=score,
        relation_type=relation_type,
    )
    session.add(edge)
    session.flush()
    return edge


def get_edges_for_doc(session: Session, doc_id: str) -> list[Edge]:
    stmt = select(Edge).where(
        (Edge.source_doc_id == doc_id) | (Edge.target_doc_id == doc_id)
    )
    return list(session.scalars(stmt))
