from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import asyncio
import logging
import colorlog
import signal
from config.config_manager import config
from service.socket_service import SocketService
from service.ai_service import AIService
from service.http_service import HttpService
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os
from fastapi import HTTPException

def setup_logging():
    """配置日志系统"""
    # 清除现有的handlers
    root_logger = logging.getLogger()
    if root_logger.handlers:
        for handler in root_logger.handlers:
            root_logger.removeHandler(handler)
            
    # 创建color formatter
    formatter = colorlog.ColoredFormatter(
        '%(asctime)s - %(log_color)s%(levelname)s%(reset)s [in %(pathname)s:%(lineno)d] - %(message)s',
        log_colors={
            'DEBUG': 'cyan',
            'INFO': 'green',
            'WARNING': 'yellow',
            'ERROR': 'red',
            'CRITICAL': 'red,bg_white',
        },
        secondary_log_colors={},
        style='%'
    )
    
    # 添加控制台handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)
    
    # 设置日志级别
    root_logger.setLevel(config.get('logging.level', 'INFO'))
    
    # 设置第三方库的日志级别
    for logger_name, level in config.get('logging.ignored_loggers', {}).items():
        logging.getLogger(logger_name).setLevel(level)

# 配置日志
setup_logging()
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Chat Verse AI Worker",
    docs_url=None,
    redoc_url=None
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 初始化服务
socket_service = SocketService()
ai_service = AIService()
http_service = HttpService(socket_service, ai_service)

# 注册 WebSocket 路由
app.mount("/ws", socket_service.get_app())

# 注册 HTTP 路由
http_service.register_routes(app)

# 挂载上传目录为静态资源
app.mount("/static/uploads", StaticFiles(directory="./data/uploads"), name="uploads")

# 添加文档查看路由
@app.get("/api/static/documents/{doc_id}/view")
async def view_document(doc_id: str):
    """在浏览器中查看文档"""
    doc_info = await http_service.document_service.get_document(doc_id)
    
    if not doc_info:
        raise HTTPException(status_code=404, detail="Document not found")
    
    file_path = doc_info["save_path"]
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    
    # 返回文件以便浏览器直接查看
    return FileResponse(
        path=file_path, 
        # filename=doc_info["original_filename"],
        media_type=doc_info["content_type"]
    )

@app.on_event("startup")
async def startup_event():
    """应用启动时的处理"""
    try:
        await socket_service.start()
        logger.info("Socket service started successfully")
    except Exception as e:
        logger.error(f"Failed to start socket service: {str(e)}")
        raise

@app.on_event("shutdown")
async def shutdown_event():
    """应用关闭时的处理"""
    try:
        await socket_service.stop()
        logger.info("Socket service stopped successfully")
    except Exception as e:
        logger.error(f"Error stopping socket service: {str(e)}")

async def shutdown(signal_name):
    """优雅退出"""
    logger.info(f"Received exit signal {signal_name}")
    
    # 给异步操作预留时间
    tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    logger.info(f"Cancelling {len(tasks)} outstanding tasks")
    
    # 取消所有任务
    [task.cancel() for task in tasks]
    
    # 等待清理完成
    logger.info("Cleaning up resources...")
    await shutdown_event()
    
    # 等待所有任务完成
    await asyncio.gather(*tasks, return_exceptions=True)
    logger.info("Shutdown complete.")

async def main():
    uv_config = uvicorn.Config(
        "main:app",
        host="0.0.0.0",
        port=config.worker['port'],
        reload=False,
        workers=1,
        log_config=None
    )
    server = uvicorn.Server(uv_config)
    
    # 设置信号处理
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_event_loop().add_signal_handler(
            sig,
            lambda s=sig: asyncio.create_task(shutdown(signal.Signals(s).name))
        )
    
    try:
        await server.serve()
    except KeyboardInterrupt:
        logger.info("Received KeyboardInterrupt")
        await shutdown("SIGINT")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        logger.info("Shutdown complete") 