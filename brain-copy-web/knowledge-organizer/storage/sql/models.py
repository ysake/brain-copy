import uuid
from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def _uuid() -> str:
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class Document(Base):
    __tablename__ = "documents"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    title: Mapped[str] = mapped_column(String(512), nullable=False)
    source: Mapped[str | None] = mapped_column(String(1024))
    content_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    raw_text: Mapped[str] = mapped_column(Text)
    summary: Mapped[str | None] = mapped_column(Text)
    tags: Mapped[list | None] = mapped_column(JSON)
    meta: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    chunks: Mapped[list["Chunk"]] = relationship(
        back_populates="document", cascade="all, delete-orphan"
    )
    memberships: Mapped[list["CollectionMember"]] = relationship(back_populates="document")
    outgoing_edges: Mapped[list["Edge"]] = relationship(
        foreign_keys="Edge.source_doc_id", back_populates="source_doc"
    )
    incoming_edges: Mapped[list["Edge"]] = relationship(
        foreign_keys="Edge.target_doc_id", back_populates="target_doc"
    )


class Chunk(Base):
    __tablename__ = "chunks"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    document_id: Mapped[str] = mapped_column(ForeignKey("documents.id"), index=True)
    chunk_index: Mapped[int] = mapped_column(Integer)
    text: Mapped[str] = mapped_column(Text)
    token_count: Mapped[int | None] = mapped_column(Integer)
    vector_id: Mapped[str | None] = mapped_column(String(36))  # Qdrant point id
    summary: Mapped[str | None] = mapped_column(Text)
    meta: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    document: Mapped["Document"] = relationship(back_populates="chunks")


class Collection(Base):
    __tablename__ = "collections"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String(256), unique=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    summary: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    members: Mapped[list["CollectionMember"]] = relationship(back_populates="collection")


class CollectionMember(Base):
    __tablename__ = "collection_members"
    __table_args__ = (UniqueConstraint("collection_id", "document_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    collection_id: Mapped[str] = mapped_column(ForeignKey("collections.id"), index=True)
    document_id: Mapped[str] = mapped_column(ForeignKey("documents.id"), index=True)

    collection: Mapped["Collection"] = relationship(back_populates="members")
    document: Mapped["Document"] = relationship(back_populates="memberships")


class Edge(Base):
    """ドキュメント間の関連エッジ"""

    __tablename__ = "edges"
    __table_args__ = (UniqueConstraint("source_doc_id", "target_doc_id", "relation_type"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    source_doc_id: Mapped[str] = mapped_column(ForeignKey("documents.id"), index=True)
    target_doc_id: Mapped[str] = mapped_column(ForeignKey("documents.id"), index=True)
    score: Mapped[float] = mapped_column(Float)
    relation_type: Mapped[str] = mapped_column(String(64), default="similar")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    source_doc: Mapped["Document"] = relationship(
        foreign_keys=[source_doc_id], back_populates="outgoing_edges"
    )
    target_doc: Mapped["Document"] = relationship(
        foreign_keys=[target_doc_id], back_populates="incoming_edges"
    )
