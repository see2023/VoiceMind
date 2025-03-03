from fastapi import FastAPI, HTTPException, Request, Response
import logging
from config.config_manager import config
from service.ai_service import AIService
from tools.json_tools import extract_json_from_text
import json
import os
import asyncio
from fastapi import UploadFile, Form, File, Body, Query, Path, Depends
from fastapi.responses import JSONResponse
from typing import Optional, List, Dict, Any
from .document_service import DocumentService

logger = logging.getLogger(__name__)

class HttpService:
    def __init__(self, socket_service, ai_service: AIService, base_path: str = "."):
        self.socket_service = socket_service
        self.ai_service = ai_service
        self.base_path = base_path
        self.document_service = DocumentService(base_path)
        # 文档处理状态存储
        self.document_tasks = {}
        # 确保上传目录存在
        os.makedirs("uploads", exist_ok=True)

    async def switch_meeting(self, meeting_id: int = Form(...)):
        """切换会议"""
        try:
            logging.info(f"Switching to meeting ID: {meeting_id}")
            
            success = await self.socket_service.switch_meeting(meeting_id)
            if not success:
                raise HTTPException(status_code=500, detail="Failed to switch meeting")
                
            return {"success": True, "status": "success"}
            
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid meeting ID: {str(e)}")
        except Exception as e:
            logging.error(f"Error switching meeting: {str(e)}")
            raise HTTPException(status_code=500, detail=str(e))

    async def analyze_dialog(self, data: Dict[str, Any] = Body(...)):
        """分析对话内容"""
        try:
            messages = data.get('messages', [])
            
            # 调用 AI 服务处理
            response = await self.ai_service.generate_response(
                messages=messages,
                model=config.llm.get('model'),
                json_mode=True
            )
            
            # 解析返回结果
            try:
                result = extract_json_from_text(response)
                return result
            except json.JSONDecodeError:
                logger.error(f"Invalid JSON response from AI: {response}")
                raise HTTPException(
                    status_code=500, 
                    detail="AI returned invalid JSON response"
                )
                
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid request: {str(e)}")
        except Exception as e:
            logger.error(f"Error analyzing dialog: {str(e)}")
            raise HTTPException(status_code=500, detail=str(e))
        
    async def upload_document(self, 
                            file: UploadFile = File(...),
                            doc_type: str = Form("unknown"),
                            title: Optional[str] = Form(None),
                            description: Optional[str] = Form(None),
                            visibility: str = Form("private"),
                            meeting_id: Optional[int] = Form(None)):
        """上传文档"""
        try:
            # 读取文件内容
            file_content = await file.read()
            original_filename = file.filename
            content_type = file.content_type
                    
            # 创建文档
            doc_info = await self.document_service.create_document(
                file_content=file_content,
                original_filename=original_filename,
                content_type=content_type,
                doc_type=doc_type,
                title=title,
                description=description,
                visibility=visibility,
                meeting_id=meeting_id
            )
            
            # 启动异步处理
            asyncio.create_task(self.document_service.process_document(doc_info["doc_id"]))
            
            return {
                "success": True,
                "doc_id": doc_info["doc_id"],
                "file_info": {
                    "original_filename": doc_info["original_filename"],
                    "content_type": doc_info["content_type"],
                    "file_path": doc_info["save_path"],
                    "file_size": os.path.getsize(doc_info["save_path"])
                }
            }
            
        except Exception as e:
            logger.error(f"Error uploading document: {str(e)}")
            raise HTTPException(status_code=400, detail=str(e))
            
    async def get_document_status(self, doc_id: str = Path(...)):
        """获取文档处理状态"""
        doc_info = await self.document_service.get_document(doc_id)
        
        if not doc_info:
            raise HTTPException(status_code=404, detail="Document not found")
            
        return {
            "success": True,
            "status": doc_info["status"],
            "progress": doc_info["progress"],
            "message": doc_info.get("message")
        }
        
    async def get_document_preview(self, doc_id: str = Path(...)):
        """获取文档结构预览"""
        doc_info = await self.document_service.get_document(doc_id)
        
        if not doc_info:
            raise HTTPException(status_code=404, detail="Document not found")
            
        # TODO: 实现文档结构解析
        structure = {
            "hierarchy": [
                {
                    "level": 1,
                    "title": "第一章",
                    "id": "ch1",
                    "children": 2
                }
            ],
            "total_chunks": 10,
            "sample_chunks": [
                {
                    "id": "chunk1",
                    "text": "示例文本内容...",
                    "hierarchy_path": ["第一章"]
                }
            ]
        }
        
        return {
            "success": True,
            "doc_id": doc_id,
            "title": doc_info["title"],
            "doc_type": doc_info["doc_type"],
            "content_type": doc_info["content_type"],
            "structure": structure
        }
        
    async def list_documents(self, 
                           meeting_id: Optional[int] = Query(None),
                           doc_type: Optional[str] = Query(None),
                           visibility: str = Query("all"),
                           query: Optional[str] = Query(None),
                           page: int = Query(1),
                           limit: int = Query(20)):
        """获取文档列表"""
        result = await self.document_service.list_documents(
            meeting_id=meeting_id,
            doc_type=doc_type,
            visibility=visibility,
            query=query,
            page=page,
            limit=limit
        )
        
        return {
            "success": True,
            **result
        }
        
    async def update_document(self, 
                            doc_id: str = Path(...),
                            data: Dict[str, Any] = Body(...)):
        """更新文档信息"""
        doc_info = await self.document_service.update_document(doc_id, data)
        if not doc_info:
            raise HTTPException(status_code=404, detail="Document not found")
            
        return {
            "success": True,
            "doc_info": doc_info
        }
        
    async def delete_document(self, doc_id: str = Path(...)):
        """删除文档"""
        success = await self.document_service.delete_document(doc_id)
        
        if not success:
            raise HTTPException(status_code=404, detail="Document not found")
            
        return {
            "success": True
        }
        
    async def query_documents(self, data: Dict[str, Any] = Body(...)):
        """查询文档内容"""
        query_text = data.get("query")
        if not query_text:
            raise HTTPException(status_code=400, detail="Query text is required")
            
        meeting_id = data.get("meeting_id")
        doc_ids = data.get("filter", {}).get("doc_ids")
        doc_types = data.get("filter", {}).get("doc_types")
        visibility = data.get("filter", {}).get("visibility", "all")
        limit = data.get("limit", 5)
        
        results = await self.document_service.query_documents(
            query_text=query_text,
            meeting_id=meeting_id,
            doc_ids=doc_ids,
            doc_types=doc_types,
            visibility=visibility,
            limit=limit
        )
        
        return {
            "success": True,
            "results": results
        }

    def register_routes(self, app: FastAPI):
        """注册所有 HTTP 路由"""
        # 会话管理
        app.post("/api/switch_meeting")(self.switch_meeting)
        app.post("/api/analyze_dialogue")(self.analyze_dialog)
        
        # 文档管理
        app.post("/api/documents/upload")(self.upload_document)
        app.get("/api/documents/{doc_id}/status")(self.get_document_status)
        app.get("/api/documents/{doc_id}/preview")(self.get_document_preview)
        app.get("/api/documents")(self.list_documents)
        app.patch("/api/documents/{doc_id}")(self.update_document)
        app.delete("/api/documents/{doc_id}")(self.delete_document)
        app.post("/api/documents/query")(self.query_documents) 