import os
import json
import asyncio
import logging
from datetime import datetime
from typing import Optional, Dict, List, Any
import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer
from parsers.text_parser import parse_text

logger = logging.getLogger(__name__)

class DocumentService:
    def __init__(self, base_path: str = "."):
        # 基础路径
        self.base_path = base_path
        self.uploads_dir = os.path.join(base_path, "data", "uploads")
        self.metadata_file = os.path.join(base_path, "data", "documents", "metadata.json")
        
        # 确保目录存在
        os.makedirs(self.uploads_dir, exist_ok=True)
        os.makedirs(os.path.dirname(self.metadata_file), exist_ok=True)
        
        # 初始化锁
        self.metadata_lock = asyncio.Lock()
        
        # 初始化 Chroma
        persist_dir = os.path.join(base_path, "data", "chroma_db")
        self.chroma_client = chromadb.PersistentClient(path=persist_dir)
        
        # 获取或创建文档集合
        self.collection = self.chroma_client.get_or_create_collection(
            name="documents",
            metadata={"description": "文档集合"}
        )
        
        # 初始化嵌入模型
        self.embedding_model = SentenceTransformer('BAAI/bge-m3')
        
        # 加载元数据
        self.load_metadata()

    def load_metadata(self) -> None:
        """加载文档元数据"""
        if os.path.exists(self.metadata_file):
            with open(self.metadata_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                self.documents = data.get("documents", {})
        else:
            self.documents = {}
            self.save_metadata()

    async def save_metadata(self) -> None:
        """保存文档元数据"""
        async with self.metadata_lock:
            try:
                with open(self.metadata_file, 'w', encoding='utf-8') as f:
                    json.dump({
                            "documents": self.documents,
                            "last_updated": datetime.now().timestamp()
                        }, f, ensure_ascii=False, indent=2)
                logger.info(f"saved metadata to {self.metadata_file}")
            except Exception as e:
                logger.error(f"Error saving metadata: {e}")

    def get_mime_extension(self, content_type: str) -> str:
        """获取MIME类型对应的文件扩展名"""
        mime_to_ext = {
            'application/pdf': '.pdf',
            'application/msword': '.doc',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
            'text/plain': '.txt',
            'text/markdown': '.md',
            'text/html': '.html'
        }
        return mime_to_ext.get(content_type, '')

    async def create_document(self, 
                            file_content: bytes,
                            original_filename: str,
                            content_type: str,
                            doc_type: str,
                            title: Optional[str] = None,
                            description: Optional[str] = None,
                            visibility: str = "private",
                            meeting_id: Optional[int] = None) -> Dict[str, Any]:
        """创建新文档"""
        from uuid import uuid4
        
        # 生成文档ID
        doc_id = str(uuid4())
        
        # 获取文件扩展名
        file_extension = os.path.splitext(original_filename)[1]
        if not file_extension:
            file_extension = self.get_mime_extension(content_type)
            
        # 保存文件
        save_filename = f"{doc_id}{file_extension}"
        save_path = os.path.join(self.uploads_dir, save_filename)
        
        with open(save_path, "wb") as f:
            f.write(file_content)
            
        # 创建文档信息
        doc_info = {
            "doc_id": doc_id,
            "original_filename": original_filename,
            "save_path": save_path,
            "content_type": content_type,
            "file_extension": file_extension,
            "doc_type": doc_type,
            "title": title or original_filename,
            "description": description,
            "visibility": visibility,
            "meeting_id": meeting_id if visibility == "private" else None,
            "status": "uploaded",
            "created_at": datetime.now().timestamp(),
            "updated_at": datetime.now().timestamp(),
            "progress": 0
        }
        
        # 保存元数据
        self.documents[doc_id] = doc_info
        await self.save_metadata()
        
        return doc_info

    async def process_document(self, doc_id: str) -> None:
        """处理文档"""
        doc_info = self.documents.get(doc_id)
        if not doc_info:
            logger.error(f"Document {doc_id} not found")
            return
            
        try:
            # 更新状态
            doc_info["status"] = "processing"
            doc_info["progress"] = 10
            await self.save_metadata()
            
            # 1. 解析文档结构
            file_path = doc_info["save_path"]
            content_type = doc_info["content_type"]
            
            # 根据文件类型选择解析方法
            if content_type == "text/plain" or doc_info["file_extension"].lower() in ['.txt', '.md']:
                with open(file_path, 'r', encoding='utf-8') as f:
                    text = f.read()
                parsed_doc = parse_text(text)
                if "error" in parsed_doc:
                    logger.error(f"Error parsing document: {parsed_doc['error']}")
                    doc_info["status"] = "error"
                    doc_info["message"] = parsed_doc["error"]
                    await self.save_metadata()
                    return
                logger.info(f"Parsed document, got {len(parsed_doc['chunks'])} chunks")
                
                # 更新进度
                doc_info["progress"] = 30
                # 保存文档结构
                doc_info["structure"] = parsed_doc["structure"]
                doc_info["chunks_count"] = len(parsed_doc["chunks"])
                await self.save_metadata()
                logger.info(f"saved metadata")
                
                # 2. 生成嵌入向量并存入 Chroma
                await self._store_chunks_in_chroma(doc_id, doc_info, parsed_doc["chunks"])
                logger.info(f"stored chunks in chroma")
            else:
                # 暂不支持其他类型，标记为完成
                logger.warning(f"Unsupported document type: {content_type}, marking as completed")
                doc_info["structure"] = []
                doc_info["chunks_count"] = 0
            
            # 更新状态
            doc_info["status"] = "completed"
            doc_info["progress"] = 100
            await self.save_metadata()
            
        except Exception as e:
            logger.error(f"Error processing document {doc_id}: {str(e)}")
            doc_info["status"] = "error"
            doc_info["message"] = str(e)
            await self.save_metadata()
    
    async def _store_chunks_in_chroma(self, doc_id: str, doc_info: Dict[str, Any], chunks: List[Dict[str, Any]]) -> None:
        """将文档块存入 Chroma"""
        if not chunks:
            return
            
        # 批量处理，每批50个
        batch_size = 50
        total_chunks = len(chunks)
        
        for i in range(0, total_chunks, batch_size):
            batch = chunks[i:i+batch_size]
            
            # 准备数据
            texts = [chunk["text"] for chunk in batch]
            ids = [f"{doc_id}_{chunk['id']}" for chunk in batch]
            
            # 生成嵌入向量
            embeddings = self.embedding_model.encode(texts).tolist()
            
            # 准备元数据
            metadatas = []
            for chunk in batch:
                metadata = {
                    "doc_id": doc_id,
                    "chunk_id": chunk["id"],
                    "doc_title": doc_info["title"],
                    "doc_type": doc_info["doc_type"],
                    "visibility": doc_info["visibility"],
                    "meeting_id": doc_info["meeting_id"],
                    "hierarchy": json.dumps(chunk["hierarchy"])
                }
                metadatas.append(metadata)
            
            # 存入 Chroma
            self.collection.add(
                documents=texts,
                embeddings=embeddings,
                metadatas=metadatas,
                ids=ids
            )
            
            # 更新进度
            progress = 30 + int(70 * (i + len(batch)) / total_chunks)
            doc_info["progress"] = min(progress, 99)  # 保留最后1%给最终完成
            await self.save_metadata()

    async def get_document(self, doc_id: str) -> Optional[Dict[str, Any]]:
        """获取文档信息"""
        return self.documents.get(doc_id)

    async def update_document(self,
                            doc_id: str,
                            updates: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """更新文档信息"""
        doc_info = self.documents.get(doc_id)
        if not doc_info:
            return None
            
        # 更新字段
        for key, value in updates.items():
            if key in ["title", "description", "doc_type", "visibility", "meeting_id"]:
                doc_info[key] = value
                
        doc_info["updated_at"] = datetime.now().timestamp()
        await self.save_metadata()
        
        # 更新 Chroma 中的元数据
        try:
            # 查询所有与该文档相关的块
            results = self.collection.get(
                where={"doc_id": doc_id}
            )
            
            if results and results["ids"]:
                # 更新每个块的元数据
                for i, chunk_id in enumerate(results["ids"]):
                    metadata = results["metadatas"][i]
                    
                    # 更新需要同步的字段
                    metadata["doc_title"] = doc_info["title"]
                    metadata["doc_type"] = doc_info["doc_type"]
                    metadata["visibility"] = doc_info["visibility"]
                    metadata["meeting_id"] = doc_info["meeting_id"]
                    
                    # 更新 Chroma 中的元数据
                    self.collection.update(
                        ids=[chunk_id],
                        metadatas=[metadata]
                    )
        except Exception as e:
            logger.error(f"Error updating Chroma metadata for document {doc_id}: {str(e)}")
        
        return doc_info

    async def delete_document(self, doc_id: str) -> bool:
        """删除文档"""
        doc_info = self.documents.get(doc_id)
        if not doc_info:
            return False
            
        # 删除文件
        if os.path.exists(doc_info["save_path"]):
            os.remove(doc_info["save_path"])
            
        # 删除元数据
        del self.documents[doc_id]
        await self.save_metadata()
        
        # 从 Chroma 中删除文档
        try:
            self.collection.delete(
                where={"doc_id": doc_id}
            )
        except Exception as e:
            logger.error(f"Error deleting document {doc_id} from Chroma: {str(e)}")
        
        return True

    async def query_documents(self,
                            query_text: str,
                            meeting_id: Optional[int] = None,
                            doc_ids: Optional[List[str]] = None,
                            doc_types: Optional[List[str]] = None,
                            visibility: str = "all",
                            limit: int = 5) -> List[Dict[str, Any]]:
        """查询文档内容"""
        # 生成查询向量
        query_embedding = self.embedding_model.encode(query_text).tolist()
        
        # 构建过滤条件
        where_clause = {}
        
        # 可见性过滤
        if visibility != "all":
            if visibility == "public":
                where_clause["visibility"] = "public"
            else:
                # 复杂条件需要使用 Chroma 的 where 语法
                # 注意：这里简化处理，实际 Chroma 可能需要不同的语法
                where_clause["$or"] = [
                    {"visibility": "public"},
                    {"$and": [
                        {"visibility": "private"},
                        {"meeting_id": meeting_id}
                    ]} if meeting_id else {}
                ]
        
        # 文档ID过滤
        if doc_ids:
            where_clause["doc_id"] = {"$in": doc_ids}
            
        # 文档类型过滤
        if doc_types:
            where_clause["doc_type"] = {"$in": doc_types}
            
        # 执行查询
        try:
            results = self.collection.query(
                query_embeddings=[query_embedding],
                where=where_clause,
                n_results=limit,
                include=["documents", "metadatas", "distances"]
            )
            
            # 处理结果
            response = []
            if results and results["ids"] and results["ids"][0]:
                for i, chunk_id in enumerate(results["ids"][0]):
                    metadata = results["metadatas"][0][i]
                    text = results["documents"][0][i]
                    distance = results["distances"][0][i]
                    
                    # 解析层级结构
                    hierarchy = json.loads(metadata["hierarchy"])
                    
                    # 生成引用信息
                    citation = self._generate_citation(metadata["doc_title"], hierarchy)
                    
                    response.append({
                        "chunk_id": metadata["chunk_id"],
                        "text": text,
                        "doc_id": metadata["doc_id"],
                        "doc_title": metadata["doc_title"],
                        "visibility": metadata["visibility"],
                        "score": 1.0 - min(distance, 1.0),  # 转换距离为相似度分数
                        "hierarchy": hierarchy,
                        "citation": citation
                    })
                    
            return response
            
        except Exception as e:
            logger.error(f"Error querying documents: {str(e)}")
            # 返回空结果
            return []
    
    def _generate_citation(self, doc_title: str, hierarchy: List[Dict[str, Any]]) -> str:
        """生成引用信息"""
        citation_parts = [f"《{doc_title}》"]
        
        for level in hierarchy:
            if level.get("level") == 1:  # 章
                citation_parts.append(f"第{level.get('number')}章")
            elif level.get("level") == 2:  # 节
                citation_parts.append(f"第{level.get('number')}节")
            elif level.get("level") == 3:  # 条
                citation_parts.append(f"第{level.get('number')}条")
                
        return "，".join(citation_parts)

    async def list_documents(self,
                           meeting_id: Optional[int] = None,
                           doc_type: Optional[str] = None,
                           visibility: str = "all",
                           query: Optional[str] = None,
                           page: int = 1,
                           limit: int = 20) -> Dict[str, Any]:
        """获取文档列表"""
        filtered_docs = []
        
        for doc_id, doc_info in self.documents.items():
            # 可见性过滤
            if visibility != "all":
                if visibility == "public" and doc_info["visibility"] != "public":
                    continue
                if visibility == "private":
                    if doc_info["visibility"] != "private" or doc_info["meeting_id"] != meeting_id:
                        continue
                        
            # 会议ID过滤
            if meeting_id and doc_info["visibility"] == "private":
                if doc_info["meeting_id"] != meeting_id:
                    continue
                    
            # 文档类型过滤
            if doc_type and doc_info["doc_type"] != doc_type:
                continue
                
            # 关键词过滤
            if query:
                if query.lower() not in doc_info["title"].lower():
                    continue
                    
            filtered_docs.append(doc_info)
            
        # 排序（按更新时间倒序）
        filtered_docs.sort(key=lambda x: x["updated_at"], reverse=True)
        
        # 分页
        total = len(filtered_docs)
        start_idx = (page - 1) * limit
        end_idx = start_idx + limit
        paged_docs = filtered_docs[start_idx:end_idx]
        
        return {
            "documents": paged_docs,
            "total": total,
            "page": page,
            "limit": limit
        } 