from dataclasses import dataclass
from typing import List, Optional, Tuple, Union, Dict, Any
import numpy as np
import time
import logging
from collections import deque

logger = logging.getLogger(__name__)


@dataclass
class AudioFrame:
    """音频帧数据结构
    存储格式统一为 int16, 范围 [-32768, 32767]
    """
    audio: np.ndarray      # 音频数据 (int16)
    start_time: float      # 该帧的开始时间
    end_time: float        # 该帧的结束时间
    duration: float        # 持续时间(秒)


class AudioBuffer:
    """音频缓冲区管理类"""
    def __init__(self, max_duration: float = 300.0, sample_rate: int = 16000):
        """初始化音频缓冲区
        
        Args:
            max_duration: 最大缓存时长(秒)，默认300秒
            sample_rate: 音频采样率
        """
        self.sample_rate = sample_rate
        self.max_duration = max_duration
        self.frames = deque()
        self.total_duration = 0.0
        
    def write(self, audio_data: np.ndarray, frame_duration: float, end_time: float) -> None:
        """写入音频数据"""
        # 清理过期数据
        self._cleanup()
        start_time = end_time - frame_duration  # 完全信任客户端时间戳
        new_frame = AudioFrame(
            audio=audio_data,
            start_time=start_time,
            end_time=end_time,
            duration=frame_duration
        )
        self.frames.append(new_frame)
        self.total_duration += frame_duration
        
    def read(self, start_time: float, end_time: float, 
            output_format: str = 'int16') -> Tuple[np.ndarray, float, float]:
        """精确读取指定时间范围的音频数据"""
        selected_data = []
        actual_start = None
        actual_end = None
        
        for frame in self.frames:
            frame_start = frame.start_time
            frame_end = frame.end_time
            
            # 计算重叠部分
            overlap_start = max(start_time, frame_start)
            overlap_end = min(end_time, frame_end)
            
            if overlap_start < overlap_end:
                # 计算需要截取的样本数
                total_samples = len(frame.audio)
                start_offset = int((overlap_start - frame_start) / frame.duration * total_samples)
                end_offset = int((overlap_end - frame_start) / frame.duration * total_samples)
                
                # 截取音频片段
                clipped = frame.audio[start_offset:end_offset]
                selected_data.append(clipped)
                
                # 更新实际时间边界
                if actual_start is None or overlap_start < actual_start:
                    actual_start = overlap_start
                if actual_end is None or overlap_end > actual_end:
                    actual_end = overlap_end

        if not selected_data:
            empty = np.array([], dtype=np.int16)
            return empty, 0.0, 0.0
        
        # 合并音频数据
        audio_data = np.concatenate(selected_data)
        
        # 格式转换
        if output_format == 'float32':
            audio_data = self._int16_to_float32(audio_data)
            
        return audio_data, actual_start, actual_end
    
    def read_latest(self, duration: float, 
                   output_format: str = 'int16') -> Tuple[np.ndarray, float, float]:
        """读取最近指定时长的音频数据
        
        Args:
            duration: 需要读取的时长(秒)
            output_format: 输出格式 ('int16' 或 'float32')
            
        Returns:
            (音频数据, 开始时间, 结束时间)
        """
        if not self.frames:
            return np.array([], dtype=np.int16), 0.0, 0.0
            
        end_time = self.frames[-1].end_time
        start_time = end_time - duration
        return self.read(start_time, end_time, output_format)

    @staticmethod
    def _int16_to_float32(audio_data: np.ndarray) -> np.ndarray:
        """将int16音频数据转换为float32格式
        
        Args:
            audio_data: int16格式的音频数据
            
        Returns:
            float32格式的音频数据，范围[-1.0, 1.0]
        """
        return audio_data.astype(np.float32) / 32768.0

    @staticmethod
    def _float32_to_int16(audio_data: np.ndarray) -> np.ndarray:
        """将float32音频数据转换为int16格式
        
        Args:
            audio_data: float32格式的音频数据，范围[-1.0, 1.0]
            
        Returns:
            int16格式的音频数据
        """
        return (audio_data * 32768.0).astype(np.int16)
    
    def clear(self) -> None:
        """清空缓冲区"""
        self.frames.clear()
        self.total_duration = 0.0
        
    def _cleanup(self) -> None:
        """清理过期数据"""
        if not self.frames:
            return
            
        current_time = time.time()
        cutoff_time = current_time - self.max_duration
        
        # 移除过期帧
        while self.frames and self.frames[0].end_time < cutoff_time:
            old_frame = self.frames.popleft()
            self.total_duration -= old_frame.duration
            
        # 如果帧数过多，也进行清理
        max_frames = int(self.max_duration * 100)  # 假设每帧10ms，5分钟约等于30000帧
        if len(self.frames) > max_frames:
            logger.warning(f"Too many frames: {len(self.frames)}, cleaning up...")
            frames_to_remove = len(self.frames) - max_frames
            removed_duration = sum(f.duration for f in self.frames[:frames_to_remove])
            self.frames = deque(self.frames[frames_to_remove:])
            self.total_duration -= removed_duration
            
    def get_stats(self) -> Dict[str, Any]:
        """获取缓冲区统计信息"""
        return {
            'frame_count': len(self.frames),
            'total_duration': self.total_duration,
            'memory_usage': sum(f.audio.nbytes for f in self.frames),
            'time_range': self.get_time_range()
        }
    
    @property
    def duration(self) -> float:
        """获取当前缓存的总时长"""
        return self.total_duration
    
    @property
    def empty(self) -> bool:
        """判断缓冲区是否为空"""
        return len(self.frames) == 0
    
    def get_time_range(self) -> Tuple[float, float]:
        """获取当前缓存的时间范围"""
        if self.empty:
            return 0.0, 0.0
        start_time = self.frames[0].start_time
        end_time = self.frames[-1].end_time
        return start_time, end_time 