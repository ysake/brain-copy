from pydantic import BaseModel, Field


class IngestRequest(BaseModel):
    text: str = Field(..., min_length=10, description="投入するテキスト")
    title: str = Field(default="untitled", description="ドキュメントタイトル")
    source: str | None = Field(default=None, description="出典URL等")
    tags: list[str] = Field(default_factory=list, description="手動タグ（省略時はLLMが付与）")
    collection: str | None = Field(default=None, description="所属コレクション名")
    auto_tag: bool = Field(default=True, description="LLMによる自動タグ付けを行うか")
    auto_summarize: bool = Field(default=True, description="LLMによる要約を生成するか")
    auto_relate: bool = Field(default=True, description="関連グラフを自動構築するか")


class IngestResponse(BaseModel):
    doc_id: str
    title: str
    chunk_count: int
    tags: list[str]
    duplicate: bool = False
    message: str = "OK"
