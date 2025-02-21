import logging
import torch
import numpy as np
from typing import Tuple, Optional
import asyncio
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor
from enum import Enum

from config.config_manager import config

logger = logging.getLogger(__name__)

@dataclass
class VADConfig:
    """VAD配置参数"""
    min_speech_duration: float  # 最小语音持续时间
    min_silence_duration: float  # 最小静音持续时间
    activation_threshold: float  # 激活阈值
    min_silence_duration_short: float  # 短停顿的最小静音持续时间
    adaptive_threshold: float  # 自适应阈值
    force_trigger: float         # 强制触发时长

class ExpFilter:
    """指数滤波器，用于平滑VAD概率值"""
    
    def __init__(self, alpha: float = 0.35):
        self.alpha = alpha
        self.last_value: Optional[float] = None
        
    def apply(self, value: float) -> float:
        if self.last_value is None:
            self.last_value = value
            return value
        
        smoothed = self.alpha * value + (1 - self.alpha) * self.last_value
        self.last_value = smoothed
        return smoothed

class VADEvent(Enum):
    SPEECH_START = "speech_start"           # 检测到开始说话
    SPEECH_END = "speech_end"               # 检测到结束说话
    SHORT_PAUSE = "short_pause"             # 检测到短停顿
    LONG_PAUSE = "long_pause"               # 检测到长停顿
    SHORT_TIMEOUT = "short_timeout"         # 短时超时
    LONG_TIMEOUT = "long_timeout"           # 长时超时

class VoiceDetector:
    """双层VAD检测模块
    
    输入要求：
    - 格式：float32
    - 范围：[-1, 1]
    - 采样率：16000Hz
    - 通道：单通道
    """
    
    def __init__(self):
        """初始化VAD检测器
        
        Args:
            use_onnx: 是否使用ONNX推理
        """
        self.sample_rate = config.audio_config['sample_rate']
        self.use_onnx = config.vad_config['use_onnx']
        self.log_vad_prob = config.vad_config['log_vad_prob']
        self.exp_filter_alpha = config.vad_config.get('exp_filter_alpha', 0.8)
        
        # 初始化模型和配置
        self._init_model()
        self._init_configs()
        
        # 状态管理
        self.quick_speech_duration = 0.0
        self.long_speech_duration = 0.0
        self.can_trigger_short_pause = True  # 新增：是否可以触发短停顿
        
        # 平滑处理
        self.exp_filter = ExpFilter(alpha=self.exp_filter_alpha)
        
        # 线程池用于模型推理
        self.executor = ThreadPoolExecutor(max_workers=1)
        
        # VAD 状态
        self.is_speaking = False
        self.silence_duration = 0.0
        
    def _init_model(self):
        """初始化VAD模型"""
        try:
            if self.use_onnx:
                model, utils = torch.hub.load(
                    repo_or_dir="snakers4/silero-vad",
                    model="silero_vad",
                    onnx=True,
                    force_reload=False
                )
            else:
                model = torch.jit.load("models/silero_vad.jit")
                model.eval()
            self.model = model
            logger.info("VAD model loaded successfully")
        except Exception as e:
            logger.error(f"Failed to load VAD model: {str(e)}")
            raise
            
    def _init_configs(self):
        """初始化VAD配置"""
        # 使用新的配置访问方式
        quick_config = config.get_vad_config(is_long=False)
        long_config = config.get_vad_config(is_long=True)
        
        # 快速VAD配置
        self.quick_config = VADConfig(
            min_speech_duration=quick_config['min_speech_duration'],
            min_silence_duration=quick_config['min_silence_duration'],
            min_silence_duration_short=quick_config['min_silence_duration_short'],
            adaptive_threshold=quick_config['adaptive_threshold'],
            activation_threshold=quick_config['activation_threshold'],
            force_trigger=quick_config['force_trigger']
        )
        
        # 长时VAD配置
        self.long_config = VADConfig(
            min_speech_duration=long_config['min_speech_duration'],
            min_silence_duration=long_config['min_silence_duration'],
            min_silence_duration_short=long_config['min_silence_duration_short'],
            adaptive_threshold=long_config['adaptive_threshold'],
            activation_threshold=long_config['activation_threshold'],
            force_trigger=long_config['force_trigger']
        )
        
    async def process_frame(self, audio_data: np.ndarray, timestamp: float) -> Optional[VADEvent]:
        """处理音频帧，返回VAD事件"""
        # 获取语音概率
        speech_prob = await self._get_speech_prob(audio_data)
        smoothed_prob = self.exp_filter.apply(speech_prob)
        
        if self.log_vad_prob:
            logger.debug(f"VAD prob: {speech_prob:.3f}, smoothed: {smoothed_prob:.3f}")
        
        # 更新状态
        frame_duration = len(audio_data) / self.sample_rate
        event = self._update_vad_state(smoothed_prob, frame_duration)
        
        if event:
            logger.info(f"VAD Event: {event.value}")
        return event
        
    def _update_vad_state(self, prob: float, frame_duration: float) -> Optional[VADEvent]:
        """更新VAD状态并返回事件"""
        is_speech = prob >= self.quick_config.activation_threshold
        
        if is_speech:
            self.silence_duration = 0
            if not self.is_speaking:
                # 开始说话
                self.is_speaking = True
                self.quick_speech_duration = 0
                self.long_speech_duration = 0
                self.can_trigger_short_pause = True  # 检测到语音开始，允许触发短停顿
                return VADEvent.SPEECH_START
            
            # 正在说话
            self.quick_speech_duration += frame_duration
            self.long_speech_duration += frame_duration
            self.can_trigger_short_pause = True  # 有语音时重置标志
            
            # 检查超时
            if self.long_speech_duration >= self.long_config.force_trigger:
                self.long_speech_duration = 0  # 重置语音时长
                return VADEvent.LONG_TIMEOUT
            elif self.quick_speech_duration >= self.quick_config.force_trigger:
                self.quick_speech_duration = 0  # 重置语音时长
                return VADEvent.SHORT_TIMEOUT
            
        else:
            if not self.is_speaking:
                return None
                
            # 累积静音时长
            self.silence_duration += frame_duration
            
            # 根据语音总长度动态调整静音阈值
            min_silence_duration = self.long_config.min_silence_duration
            if self.long_speech_duration >= self.long_config.adaptive_threshold:
                # logger.debug(f"Speech duration: {self.long_speech_duration:.3f} >= {self.long_config.adaptive_threshold:.3f}, min_silence_duration: {min_silence_duration:.3f} -> {self.long_config.min_silence_duration_short:.3f}")
                min_silence_duration = self.long_config.min_silence_duration_short
            
            # 检查停顿
            if self.silence_duration >= min_silence_duration:
                # 长停顿
                self.is_speaking = False
                self.can_trigger_short_pause = True
                return VADEvent.LONG_PAUSE
            elif self.silence_duration >= self.quick_config.min_silence_duration:
                # 短停顿
                if self.can_trigger_short_pause:
                    self.can_trigger_short_pause = False
                    return VADEvent.SHORT_PAUSE
                
        return None
        
    def _inference(self, audio_data: np.ndarray) -> float:
        """执行VAD推理
        
        Args:
            audio_data: 音频数据
            
        Returns:
            float: 语音概率
        """
        with torch.no_grad():
            return self.model(torch.from_numpy(audio_data), self.sample_rate).item()
        
    def reset(self):
        """重置VAD状态"""
        self.quick_speech_duration = 0.0
        self.long_speech_duration = 0.0
        self.exp_filter.last_value = None
        self.can_trigger_short_pause = True  # 重置短停顿触发标志
        
    async def _get_speech_prob(self, audio_data: np.ndarray) -> float:
        """获取语音概率
        
        Args:
            audio_data: 音频数据
            
        Returns:
            float: 语音概率
        """
        # 转换音频格式
        if audio_data.dtype != np.float32:
            audio_data = audio_data.astype(np.float32) / 32768.0
        
        # 在线程池中运行模型推理
        speech_prob = await asyncio.get_event_loop().run_in_executor(
            self.executor,
            self._inference,
            audio_data
        )
        
        return speech_prob