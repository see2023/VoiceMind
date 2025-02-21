import socket
import redis.asyncio
from typing import Optional
from config.config_manager import config

class RedisClient:
    _instance: Optional['RedisClient'] = None

    @classmethod
    def get_instance(cls) -> redis.asyncio.Redis:
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance.client

    def __init__(self):
        if self._instance is not None:
            raise Exception('Use get_instance() instead')
            
        redis_config = config.redis
        ssl_config = {}
        if redis_config['ssl']:
            ssl_config = {
                'ssl': True,
                'ssl_cert_reqs': 'none'
            }
            
        self.client = redis.asyncio.Redis(
            host=redis_config['host'],
            port=redis_config['port'],
            password=redis_config['password'],
            db=0,
            decode_responses=True,
            socket_keepalive=True,
            socket_timeout=60,
            health_check_interval=30,
            retry_on_timeout=True,
            socket_keepalive_options={
                socket.TCP_KEEPALIVE: 30,
                socket.TCP_KEEPINTVL: 10,
                socket.TCP_KEEPCNT: 3
            },
            **ssl_config
        )

    @staticmethod
    def key(name: str) -> str:
        """Generate Redis key with prefix"""
        return f"{config.redis['prefix']}{name}" 