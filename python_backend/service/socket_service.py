import logging
from typing import Dict, Any
import socketio
from datetime import datetime
from config.config_manager import config
import asyncio
import numpy as np
import time
from .audio_processor import AudioProcessor

logger = logging.getLogger(__name__)

class SocketService:
    def __init__(self):
        self.sio = socketio.AsyncServer(
            async_mode='asgi',
            cors_allowed_origins='*',  # 开发环境中允许所有源
            logger=True,
            engineio_logger=True
        )
        self.app = socketio.ASGIApp(self.sio)
        self.audio_processor = AudioProcessor()  # 初始化音频处理器
        self._last_stream_log_time = 0  # 添加时间戳跟踪
        self._stream_status = False  # 只保留流状态跟踪
        self.current_sid = None  # 添加当前活跃连接的跟踪
        self._event_handler_task = None  # 新增：用于跟踪事件处理任务
        self._setup_handlers()

    async def _handle_audio_events(self):
        """统一的事件处理循环"""
        while True:
            try:
                event = await self.audio_processor.get_next_event()
                
                # 检查是否有活跃连接
                if not self.current_sid:
                    logger.debug("No active connection, skipping event")
                    continue
                    
                logger.debug(f"Processing event for current client {self.current_sid}: {event}")
                
                if event['type'] == 'transcription':
                    logger.debug(f"Attempting to send transcription to current client {self.current_sid}")
                    try:
                        await self.sio.emit('transcription', {
                            'text': event['text'],
                            'speaker_id': event['speaker_id'],
                            'start_time': event['start_time'],
                            'end_time': event['end_time'],
                            'isFinal': event['isFinal'],
                            'timestamp': event['timestamp']
                        }, room=self.current_sid)
                        logger.debug(f"Successfully sent transcription to current client {self.current_sid}")
                    except Exception as e:
                        logger.error(f"Failed to send transcription to client {self.current_sid}: {str(e)}")
                        
                elif event['type'] == 'error':
                    logger.debug(f"Attempting to send error to current client {self.current_sid}")
                    await self.sio.emit('error', {
                        'code': event['code'],
                        'message': event['message'],
                    }, room=self.current_sid)
                    
            except Exception as e:
                logger.error(f"Error in _handle_audio_events: {str(e)}", exc_info=True)
                await asyncio.sleep(0.1)
                continue

    def _setup_handlers(self):
        @self.sio.event
        async def connect(sid, environ):
            logger.info(f"Client connected: {sid}")
            logger.debug(f"Connection environment: {environ}")
            
            # 更新当前活跃连接
            self.current_sid = sid
            logger.info(f"Set current active connection to {sid}")
            
            # 确保事件处理任务在运行
            if not self._event_handler_task or self._event_handler_task.done():
                self._event_handler_task = asyncio.create_task(self._handle_audio_events())
            
            await self._send_system_status(sid)

        @self.sio.event
        async def disconnect(sid):
            if sid == self.current_sid:
                logger.info(f"Active client disconnected: {sid}")
                self.current_sid = None
                if self._stream_status:
                    logger.info(f"Audio streaming stopped from client {sid}")
                    self._stream_status = False
            logger.info(f"Client disconnected: {sid}")

        @self.sio.on('audio_stream_stop')
        async def handle_stream_stop(sid):
            if self._stream_status:
                logger.info(f"Audio streaming stopped from client {sid}")
                self._stream_status = False
                # Add force processing of any pending audio segments
                await self.audio_processor.force_process_pending()

        @self.sio.on('audio_stream')
        async def handle_audio_stream(sid, data: Dict[str, Any]):
            try:
                audio_data = np.frombuffer(data['audio'], dtype=np.int16)
                timestamp = data.get('timestamp', time.time())
                # logger.debug(f"Received audio data from client {sid}, length: {len(audio_data)}, timestamp: {data.get('timestamp')}")
                
                # 只在状态变化时打印 INFO 日志
                if not self._stream_status:
                    logger.info(f"Audio streaming started from client {sid}")
                    self._stream_status = True
                
                await self.audio_processor.process_audio(
                    audio_data=audio_data,
                    timestamp=timestamp
                )
                
            except Exception as e:
                if self._stream_status:
                    logger.error(f"Audio streaming error from client {sid}: {str(e)}")
                    self._stream_status = False
                await self._send_error(sid, 1001, "Audio processing error")


    async def _send_system_status(self, sid: str):
        """发送系统状态"""
        status = {
            'status': 'ready',
            'components': {
                'audio': True,
                'llm': True,
                'rag': True
            }
        }
        await self.sio.emit('system_status', status, room=sid)

    async def _send_error(self, sid: str, code: int, message: str, context: Dict = None):
        """发送错误消息"""
        error = {
            'code': code,
            'message': message,
            'context': context
        }
        await self.sio.emit('error', error, room=sid)

    def get_app(self):
        """获取 ASGI 应用"""
        return self.app 

    async def start(self):
        """启动服务"""
        await self.audio_processor.start()
        # 启动统一的事件处理任务
        if not self._event_handler_task or self._event_handler_task.done():
            self._event_handler_task = asyncio.create_task(self._handle_audio_events())

    async def stop(self):
        """停止服务"""
        if self._event_handler_task and not self._event_handler_task.done():
            self._event_handler_task.cancel()
            try:
                await self._event_handler_task
            except asyncio.CancelledError:
                pass
        await self.audio_processor.stop() 

    async def _process_audio_event(self, event):
        try:
            # 确保事件包含所有必需字段
            if not all(k in event for k in ['type', 'text', 'speaker_id', 'start_time', 'end_time']):
                missing = [k for k in ['type', 'text', 'speaker_id', 'start_time', 'end_time'] if k not in event]
                logger.error(f"Missing required fields in event: {missing}")
                return
            
            # 处理事件
            if event['type'] in ['quick_asr_result', 'final_asr_result']:
                await self.send_json({
                    'type': event['type'],
                    'text': event['text'],
                    'speaker_id': event['speaker_id'],
                    'start_time': event['start_time'],
                    'end_time': event['end_time']
                })
            elif event['type'] == 'speaker_detected':
                await self.send_json({
                    'type': event['type'],
                    'speaker_id': event['speaker_id'],
                    'timestamp': event['timestamp']
                })
        except Exception as e:
            logger.error(f"Error processing audio event: {str(e)}", exc_info=True) 

    async def switch_meeting(self, meeting_id: int):
        """切换会议"""
        try:
            # 使用 audio_processor 中的 speaker_detector
            await self.audio_processor.speaker_detector.switch_meeting(meeting_id)
            return True
        except Exception as e:
            logging.error(f"Error switching meeting: {e}")
            return False 