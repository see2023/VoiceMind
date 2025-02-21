from datetime import datetime, timedelta
from typing import List, Dict
import json
from core.redis_client import RedisClient
from service.ai_models import Message, MessageRole
import logging

logger = logging.getLogger(__name__)

class MessageTools:
    def __init__(self):
        self.redis = RedisClient.get_instance()
        self.message_expire_days = 7

    def get_timestr(self, timestamp_ms: int) -> str:
        # 返回可读的时间字符串，格式为：%d 分钟/之前，%d 小时/之前，%d 天/之前
        if not timestamp_ms:
            return ""
        
        now = datetime.now()
        delta = now - datetime.fromtimestamp(timestamp_ms / 1000)
        if delta.days > 0:
            return f"[{delta.days} days ago]"
        elif delta.seconds >= 3600:
            return f"[{delta.seconds // 3600} hours ago]"
        elif delta.seconds >= 60:
            return f"[{delta.seconds // 60} minutes ago]"
        else:
            return "[just now]"

    async def get_conversation_history(self, user_id: str, days_back: int = 2) -> List[Message]:
        """获取用户的对话历史
        
        Args:
            user_id: 用户ID
            days_back: 往前查找的天数，默认2天
        """
        try:
            messages = []
            today = datetime.now()
            
            # 遍历最近几天的消息
            for i in range(days_back):
                date = (today - timedelta(days=i)).strftime('%Y-%m-%d')
                key = RedisClient.key(f'messages:{user_id}:{date}')
                
                # 获取当天的消息
                message_list = await self.redis.lrange(key, 0, -1)
                if message_list:
                    for msg_str in message_list:
                        try:
                            msg_data = json.loads(msg_str)
                            timestr = self.get_timestr(msg_data.get('timestamp', 0))
                            messages.append(Message(
                                role=MessageRole.user if msg_data.get('role', 'user') == 'user' else MessageRole.assistant,
                                content=timestr + msg_data.get('content', '')
                            ))
                        except json.JSONDecodeError:
                            logger.error(f"Failed to parse message: {msg_str}")
                            continue
                
                # 如果已经找到了消息，就不用继续往前找了
                if messages:
                    break
                    
            # 返回最近的N条消息
            max_messages = 10  # 限制历史消息数量
            return messages[-max_messages:] if messages else []
            
        except Exception as e:
            logger.error(f"Error getting conversation history for user {user_id}: {e}")
            return []

    async def save_message(self, user_id: str, message: Message):
        """保存消息，设置7天过期"""
        try:
            today = datetime.now().strftime('%Y-%m-%d')
            messages_key = RedisClient.key(f'messages:{user_id}:{today}')
            
            message_data = {
                'role': message.role.name,
                'content': message.content,
                'timestamp': int(datetime.now().timestamp() * 1000)  # use ms timestamp
            }
            
            # 保存消息
            await self.redis.rpush(messages_key, json.dumps(message_data))
            
            # 设置过期时间
            expire_at = datetime.now() + timedelta(days=self.message_expire_days)
            await self.redis.expireat(messages_key, int(expire_at.timestamp()))
            
            logger.debug(f"Saved message for user {user_id}, role: {message.role.name}")
            
        except Exception as e:
            logger.error(f"Failed to save message for user {user_id}: {e}")
            raise  # 这里需要抛出异常，因为消息保存失败是严重错误