# RAG 设计文档 - 智能语音助手

## 1. 概述

本文档描述了智能语音助手中检索增强生成（RAG）功能的设计和实现方案。该功能旨在为辩论场景提供实时、准确的参考信息，主要支持法律文档和教材等结构化资料的管理、检索和应用。

## 2. 系统架构

### 2.1 总体架构

系统采用客户端-服务器架构：

- **客户端（Flutter）**：负责用户界面、文档上传、预览和管理
- **服务器（Python）**：负责文档处理、嵌入生成、向量检索和与 LLM 集成

```
+----------------+                  +------------------+
|                |  文档上传/查询   |                  |
|  Flutter 客户端 | --------------> |  Python 服务器    |
|                | <-------------- |                  |
+----------------+  结构化结果/建议  +------------------+
       |                                    |
       v                                    v
+----------------+                  +------------------+
|                |                  |                  |
|    Isar DB     |                  |     Chroma DB    |
|  (元数据存储)   |                  | (向量+元数据+内容) |
|                |                  |                  |
+----------------+                  +------------------+
```

### 2.2 技术选择

- **向量数据库**：Chroma DB (集成向量存储和元数据管理)
- **嵌入模型**：BGEM3 (支持中文的高质量嵌入模型)
- **客户端存储**：Isar DB (Flutter 本地数据库)

## 3. 文档管理流程

### 3.1 文档上传与处理

1. **上传流程**：

   - 用户通过 Flutter 界面上传文档
   - 客户端将文档传输至 Python 后端
   - 后端解析文档结构和内容
   - 返回结构化预览给客户端确认
   - 用户确认后进行最终处理和存储

2. **文档解析**：
   - 自动检测文档类型（法律、教材等）
   - 根据文档类型应用相应的解析规则
   - 提取层级结构（章节、条款等）
   - 按照语义和结构边界进行切分
   - 生成嵌入向量

### 3.2 存储策略

1. **Chroma 存储（服务器端）**：

   - 存储文档片段的嵌入向量
   - 存储完整的元数据（包括层级结构信息）
   - 存储文档片段的原始内容
   - 支持多集合组织（按文档类型区分）
   - 支持文档可见性过滤（公共/私有）
   - 提供统一的检索接口

2. **元数据存储（服务器端）**：

   - 使用 JSON 文件持久化存储文档信息
   - 存储位置：documents/metadata.json
   - 包含字段：
     ```json
     {
       "documents": {
         "doc_id1": {
           "doc_id": "string",
           "original_filename": "string",
           "save_path": "string",
           "content_type": "string",
           "file_extension": "string",
           "doc_type": "legal|educational|article|other",
           "title": "string",
           "description": "string",
           "visibility": "public|private",
           "meeting_id": "number|null",
           "status": "string",
           "created_at": "number",
           "updated_at": "number",
           "progress": "number",
           "structure_summary": "string",
           "chunks_count": "number"
         }
       },
       "last_updated": "number"
     }
     ```

3. **Isar DB 存储（客户端）**：

   - 存储基本文档元数据
   - 记录文档状态和处理进度
   - 支持离线查看文档信息

4. **文件系统存储**：
   - 上传文件保存在 uploads 目录
   - 保留原始文件扩展名
   - 文件名格式：{doc_id}{file_extension}

### 3.3 文件处理流程

1. **文件上传**：

   - 获取文件信息（文件名、MIME 类型、扩展名）
   - 生成唯一文档 ID
   - 保存文件到 uploads 目录
   - 记录元数据到 JSON 文件
   - 启动后台处理任务

2. **文件预览**：

   - 支持常见文档格式预览（PDF、文本、HTML 等）
   - 使用上传后的文件路径
   - 根据文件类型提供不同预览方式
   - 对不支持预览的格式显示基本信息

3. **文档可见性**：
   - 公共文档：所有会议可见
   - 私有文档：仅特定会议可见
   - 上传时指定可见性和关联会议
   - 支持后续修改可见性设置

## 4. 检索和应用流程

### 4.1 自动检索流程

1. **对话分析触发**：

   - 前端将新增对话内容发送到后端
   - 后端使用 LLM 分析对话并提取关键查询点
   - 将提取的关键点转换为向量查询

2. **相关内容检索**：

   - 使用生成的查询向量在 Chroma 中搜索相似内容
   - 获取相关文档片段及其结构上下文和元数据
   - 将检索到的内容作为上下文提供给 LLM

3. **增强回复生成**：
   - LLM 利用检索到的内容生成更准确、有依据的回复
   - 回复中包含引用信息（例如法律条款出处）

### 4.2 直接查询功能（可选）

- 提供直接查询接口，便于测试和特定查询
- 用户输入查询，系统返回最相关的文档片段及其结构上下文

## 5. 文档结构处理

### 5.1 结构化解析

系统支持多种文档结构复杂度：

1. **多层级结构**（如法律文档）：

   - 标题 → 章 → 节 → 条款 → 款 → 项
   - 保留完整的层级路径

2. **中等结构**（如教材）：

   - 章 → 节 → 小节 → 段落
   - 提取标题和层级关系

3. **简单结构**（一般文章）：
   - 标题 → 段落
   - 基于语义边界进行切分

### 5.2 元数据模式

为同时支持简单和复杂结构，采用通用元数据模式：

```json
{
  "doc_id": "unique_id",
  "doc_title": "文档标题",
  "doc_type": "legal|educational|article|other",
  "hierarchy": [
    {
      "level": 1,
      "title": "第一章",
      "id": "ch1"
    },
    {
      "level": 2,
      "title": "第一节",
      "id": "sec1.1"
    }
  ],
  "chunk_id": "ch1_sec1.1_para1",
  "text": "实际内容..."
}
```

对于简单结构，hierarchy 数组可以更短或只有一个层级。

### 5.3 结构验证和修正

- 提供结构预览界面
- 允许用户校正自动检测的结构
- 提供常见文档类型的模板

## 6. 技术实现细节

### 6.1 BGEM3 嵌入模型

- 使用 BGEM3 模型生成文本嵌入
- 特别优化用于中文理解
- 通过 sentence-transformers 库实现：

```python
from sentence_transformers import SentenceTransformer

model = SentenceTransformer('BAAI/bge-m3')
embeddings = model.encode(text_chunks)
```

### 6.2 Chroma 实现

- 使用 Chroma 客户端 API 创建集合并管理文档
- 支持文档可见性和会议 ID 过滤
- 示例实现：

```python
import chromadb
from chromadb.config import Settings

# 初始化 Chroma 客户端
client = chromadb.Client(Settings(
    chroma_db_impl="duckdb+parquet",
    persist_directory="./chroma_db"
))

# 创建或获取集合
collection = client.get_or_create_collection(
    name="legal_documents",
    metadata={"description": "法律文档集合"}
)

# 添加文档
collection.add(
    documents=["文档内容..."],
    metadatas=[{
        "doc_id": "law_123",
        "doc_title": "民法典",
        "visibility": "public",
        "meeting_id": None,
        "hierarchy": [{"level": 1, "title": "第一章", "id": "ch1"}],
        "chunk_id": "ch1_para1"
    }],
    ids=["law_123_ch1_para1"]
)

# 查询文档（带可见性过滤）
results = collection.query(
    query_texts=["继承权相关规定"],
    where={
        "$or": [
            {"visibility": "public"},
            {"$and": [
                {"visibility": "private"},
                {"meeting_id": current_meeting_id}
            ]}
        ]
    },
    n_results=5
)
```

### 6.3 文档解析实现

采用多阶段流水线：

1. 文档类型检测
2. 结构检测
3. 内容切分
4. 嵌入生成

支持的文档格式：

- PDF（带文本提取）
- DOCX/DOC
- 纯文本（带类 Markdown 结构）
- HTML

## 7. API 设计

RAG 功能通过以下 API 接口提供：

### 7.1 文档管理 API

#### 上传文档

```
POST /api/documents/upload
```

- 用途：上传并处理文档
- 参数：多部分表单数据（文件、文档类型、标题、描述、可见性等）

#### 获取文档处理状态

```
GET /api/documents/{doc_id}/status
```

- 用途：获取文档处理进度和状态

#### 获取文档结构预览

```
GET /api/documents/{doc_id}/preview
```

- 用途：获取文档的结构化预览
- 返回：文档层级结构和示例内容块

#### 获取文档列表

```
GET /api/documents
```

- 用途：列出已上传的文档
- 参数：会议 ID、文档类型、可见性、分页参数等

#### 更新文档信息

```
PATCH /api/documents/{doc_id}
```

- 用途：更新文档的元数据
- 参数：标题、描述、文档类型、可见性设置等

#### 删除文档

```
DELETE /api/documents/{doc_id}
```

- 用途：删除文档及其相关资源

#### 查询文档内容

```
POST /api/documents/query
```

- 用途：直接查询文档内容（用于测试）
- 参数：查询文本、过滤器（文档 ID、类型、可见性）、限制结果数量等

## 8. 用户界面设计

### 8.1 文档管理界面

- 文档列表视图
- 上传和处理流程界面
- 结构预览和编辑界面
- 文档元数据编辑（备注等）

### 8.2 检索结果展示

- 在建议中显示引用和出处
- 支持点击查看原始上下文
- 允许用户调整相关性权重

## 9. 总结

本设计方案提供了一个轻量级、自定义的 RAG 实现，专注于结构化文档的处理和检索。通过使用 Chroma 作为向量数据库，简化了架构并提高了系统的可维护性。此方案特别适合本项目的具体需求：

1. 有限文档范围
2. 高结构化需求（法律文档、教材）
3. 本地运行保障数据安全
4. 与现有 Flutter/Python 架构集成

实现此方案将使智能语音助手能够提供基于权威参考资料的实时建议，显著提升在辩论、教学等场景下的实用性。
