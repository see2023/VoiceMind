from fastapi import FastAPI, Form, HTTPException, Request
import logging
from config.config_manager import config
from service.ai_service import AIService
from tools.json_tools import extract_json_from_text
import json

logger = logging.getLogger(__name__)

class HttpService:
    def __init__(self, socket_service, ai_service: AIService):
        self.socket_service = socket_service
        self.ai_service = ai_service

    async def switch_meeting(self, request: Request):
        """切换会议"""
        try:
            data = await request.form()
            meeting_id = int(data.get('meeting_id'))
            logging.info(f"Switching to meeting ID: {meeting_id}")
            
            success = await self.socket_service.switch_meeting(meeting_id)
            if not success:
                raise HTTPException(status_code=500, detail="Failed to switch meeting")
                
            return {"status": "success"}
            
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"Invalid meeting ID: {str(e)}")
        except Exception as e:
            logging.error(f"Error switching meeting: {str(e)}")
            raise HTTPException(status_code=500, detail=str(e))

    async def analyze_dialog(self, request: Request):
        """分析对话内容"""
        try:
            data = await request.json()
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

    async def upload_file(self):
        """文件上传处理"""
        # TODO: 实现文件上传逻辑
        pass

    def register_routes(self, app: FastAPI):
        """注册所有 HTTP 路由"""
        app.post("/switch_meeting")(self.switch_meeting)
        app.post("/analyze_dialog")(self.analyze_dialog)
        app.post("/upload")(self.upload_file) 