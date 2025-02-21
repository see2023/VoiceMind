import os
import yaml
from typing import Any, Dict
import random
import string
from pathlib import Path
import logging

logger = logging.getLogger(__name__)

class ConfigManager:
    _instance = None
    _config = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(ConfigManager, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        self.worker_id = None
        self.worker_id_file = os.getenv('WORKER_ID_FILE', '.worker_id')
        if self._config is None:
            self._load_config()

    def generate_short_id(self, prefix='py_', length=6):
        """生成短ID"""
        chars = string.ascii_uppercase + string.digits
        random_str = ''.join(random.choices(chars, k=length))
        return f"{prefix}{random_str}"

    def generate_worker_id(self) -> str:
        """生成或恢复 worker ID"""
        if self.worker_id:
            return self.worker_id

        try:
            # 尝试从文件读取
            worker_id_path = Path(self.worker_id_file)
            if worker_id_path.exists():
                worker_id = worker_id_path.read_text().strip()
                if worker_id:
                    logger.info(f"Restored worker_id: {worker_id}")
                    self.worker_id = worker_id
                    return worker_id

            # 生成新ID
            new_id = self.generate_short_id()
            
            # 保存到文件
            worker_id_path.write_text(new_id)
            logger.info(f"Generated and saved new worker_id: {new_id}")
            
            self.worker_id = new_id
            return new_id

        except Exception as e:
            logger.error(f"Failed to persist worker_id: {e}")
            # 出错时使用临时ID
            temp_id = self.generate_short_id()
            logger.warning(f"Using temporary worker_id: {temp_id}")
            self.worker_id = temp_id
            return temp_id

    def _load_config(self):
        """加载配置文件并处理环境变量覆盖"""
        config_path = Path(__file__).parent / 'config.yaml'
        
        with open(config_path, 'r', encoding='utf-8') as f:
            self._config = yaml.safe_load(f)

        # 添加运行时配置
        self._config['runtime'] = {
            'redis': {
                'host': os.getenv('REDIS_HOST', 'localhost'),
                'port': int(os.getenv('REDIS_PORT', '6379')),
                'password': os.getenv('REDIS_PASSWORD'),
                'ssl': os.getenv('REDIS_SSL', 'false').lower() == 'true',
                'prefix': os.getenv('REDIS_PREFIX', 'i:')
            },
            'worker': {
                'id': os.getenv('AI_WORKER_ID', self.generate_worker_id()),
                'max_concurrent': int(os.getenv('AI_MAX_CONCURRENT', '10')),
                'window_limit': int(os.getenv('AI_WINDOW_LIMIT', '60')),
                'port': int(os.getenv('AI_SERVICE_PORT', '9000')),
                'health_check_interval': int(os.getenv('WORKER_HEALTH_CHECK_INTERVAL', '10000'))
            }
        }

    def get(self, key: str, default: Any = None) -> Any:
        """获取配置项"""
        keys = key.split('.')
        value = self._config
        for k in keys:
            if isinstance(value, dict):
                value = value.get(k)
            else:
                return default
        return value if value is not None else default

    @property
    def redis(self) -> Dict:
        """获取Redis配置"""
        return self._config['runtime']['redis']

    @property
    def worker(self) -> Dict:
        """获取Worker配置"""
        return self._config['runtime']['worker']

    @property
    def llm(self) -> Dict:
        """获取 LLM 相关配置"""
        return self._config.get('llm', {})
    
    @property
    def speaker(self) -> Dict:
        """获取说话人识别相关配置"""
        speaker = self._config.get('audio', {}).get('speaker', {})
        return {
            'model': {
                'use_campplus': speaker.get('model', {}).get('use_campplus', True),
                'device': speaker.get('model', {}).get('device', 'cpu'),
            },
            'embedding': {
                'min_chunk_duration': speaker.get('embedding', {}).get('min_chunk_duration', 3.0),
                'max_chunk_duration': speaker.get('embedding', {}).get('max_chunk_duration', 20.0),
                'max_embeddings': speaker.get('embedding', {}).get('max_embeddings', 3),
            },
            'threshold': {
                'base': speaker.get('threshold', {}).get('base', 0.25),
                'duration_factor': speaker.get('threshold', {}).get('duration_factor', 0.25),
            },
            'storage': {
                'path': speaker.get('storage', {}).get('path', 'data/speakers.json'),
            }
        }

    @property
    def audio(self) -> Dict:
        """获取音频处理相关配置"""
        return self._config.get('audio', {})

    @property
    def vad(self) -> Dict:
        """获取 VAD 相关配置"""
        return self._config.get('vad', {})

    @property
    def buffer(self) -> Dict:
        """获取缓冲区相关配置"""
        return self._config.get('buffer', {})

    @property
    def vad_config(self) -> Dict:
        """获取 VAD 配置"""
        vad_model = self.audio.get('vad_model', {})
        return {
            'quick': {
                'min_speech_duration': vad_model.get('quick', {}).get('min_speech_duration', 0.2),
                'min_silence_duration': vad_model.get('quick', {}).get('min_silence_duration', 0.3),
                'activation_threshold': vad_model.get('quick', {}).get('activation_threshold', 0.3),
                'force_trigger': vad_model.get('quick', {}).get('force_trigger', 2.5),
            },
            'long': {
                'min_speech_duration': vad_model.get('long', {}).get('min_speech_duration', 0.5),
                'min_silence_duration': vad_model.get('long', {}).get('min_silence_duration', 0.8),
                'activation_threshold': vad_model.get('long', {}).get('activation_threshold', 0.5),
                'force_trigger': vad_model.get('long', {}).get('force_trigger', 20.0),
                'min_silence_duration_short': vad_model.get('long', {}).get('min_silence_duration_short', 0.5),
                'adaptive_threshold': vad_model.get('long', {}).get('adaptive_threshold', 3.0),
            },
            'enable_quick': vad_model.get('enable_quick', False),
            'enable_quick_timeout': vad_model.get('enable_quick_timeout', False),
            'log_vad_prob': vad_model.get('log_vad_prob', False),
            'use_onnx': vad_model.get('use_onnx', True),
            'exp_filter_alpha': vad_model.get('exp_filter_alpha', 0.8)
        }

    @property
    def buffer_config(self) -> Dict:
        """获取缓冲区配置"""
        buffer = self._config.get('buffer', {})
        return {
            'quick_buffer_duration': buffer.get('quick_buffer_duration', 60.0),
            'long_buffer_duration': buffer.get('long_buffer_duration', 300.0),
            'sample_rate': buffer.get('sample_rate', 16000)
        }

    @property
    def vad_manager_config(self) -> Dict:
        """获取 VAD 管理器配置"""
        vad_manager = self._config.get('vad_manager', {})
        return {
            'max_search_distance': vad_manager.get('max_search_distance', 2.0),
            'cleanup_interval': vad_manager.get('cleanup_interval', 60.0)
        }

    @property
    def audio_config(self) -> Dict:
        """获取音频配置"""
        audio = self._config.get('audio', {})
        return {
            'sample_rate': audio.get('sample_rate', 16000),
            'channels': audio.get('channels', 1),
            'sentence_split': {
                'enable': audio.get('sentence_split', {}).get('enable', True),
                'min_duration_for_split': audio.get('sentence_split', {}).get('min_duration_for_split', 3.0)
            },
            'asr': {
                'model': audio.get('asr', {}).get('model', 'iic/SenseVoiceSmall'),
                'language': audio.get('asr', {}).get('language', 'zh'),
                'use_onnx': audio.get('asr', {}).get('use_onnx', True),
                'output_timestamp': audio.get('asr', {}).get('output_timestamp', True)
            },
            'speaker': {
                'model': audio.get('speaker', {}).get('model', 'CAMPPlus/wespeaker'),
                'threshold': audio.get('speaker', {}).get('threshold', 0.7)
            }
        }

    def get_vad_config(self, is_long: bool = False) -> Dict:
        """获取指定类型的 VAD 配置"""
        vad_config = self.vad_config
        config_type = 'long' if is_long else 'quick'
        return {
            'min_speech_duration': vad_config[config_type]['min_speech_duration'],
            'min_silence_duration': vad_config[config_type]['min_silence_duration'],
            'min_silence_duration_short': vad_config[config_type].get('min_silence_duration_short', 0.2),
            'adaptive_threshold': vad_config[config_type].get('adaptive_threshold', 10.0),
            'activation_threshold': vad_config[config_type]['activation_threshold'],
            'force_trigger': vad_config[config_type]['force_trigger']
        }

config = ConfigManager() 