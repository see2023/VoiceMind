import logging
from typing import List, Optional, Tuple
from dataclasses import dataclass
from .voice_detector import VADEvent

logger = logging.getLogger(__name__)

@dataclass
class VADSegment:
    """VAD 片段信息"""
    event_type: VADEvent      
    start_time: float        
    end_time: float         
    is_processed: bool = False  
    speaker_id: Optional[str] = None
    asr_text: Optional[str] = None
    asr_timestamps: Optional[List[float]] = None # 取出开始时间戳 ms [[0, 210], [210, 390] ...] --> [0, 210, 390, ...]
    
    def update_recognition(self, speaker_id: str, asr_text: str, timestamps: List[float]):
        """更新识别结果"""
        self.speaker_id = speaker_id
        self.asr_text = asr_text
        self.asr_timestamps = timestamps
        self.is_processed = True

class VADManager:
    def __init__(self):
        self.segments: List[VADSegment] = []
        
    def add_segment(self, segment: VADSegment):
        """添加VAD片段"""
        self.segments.append(segment)
        
    def get_recent_segments(self, count: int = 3) -> List[VADSegment]:
        """获取最近的N个段落"""
        return self.segments[-count:] if len(self.segments) >= count else []
        
    def cleanup_old_segments(self, min_time: float):
        """清理过期片段"""
        self.segments = [s for s in self.segments if s.end_time >= min_time]
    
    def find_nearest_short_pause(self, target_time: float, max_distance: float = 10.0) -> Optional[float]:
        """查找最近的短停顿点"""
        nearest_time = None
        min_distance = float('inf')
        
        # 查找目标时间之前的最近短停顿
        for segment in reversed(self.segments):
            if segment.event_type not in [VADEvent.SHORT_PAUSE, VADEvent.SHORT_TIMEOUT]:
                continue
                
            distance = abs(target_time - segment.end_time)
            if distance > max_distance:
                break
                
            if distance < min_distance:
                min_distance = distance
                nearest_time = segment.end_time
                
        return nearest_time
    
    def get_context_segments(self, target_time: float, window: float = 5.0) -> Tuple[List[VADSegment], List[VADSegment]]:
        """获取目标时间点前后的片段"""
        before = []
        after = []
        
        for seg in self.segments:
            if seg.end_time < target_time:
                if target_time - seg.end_time <= window:
                    before.append(seg)
            elif seg.start_time > target_time:
                if seg.start_time - target_time <= window:
                    after.append(seg)
                    
        return before, after 