import logging
import numpy as np
import asyncio
from typing import Dict, Any, Optional, List, Tuple
from datetime import datetime
import time
from functools import wraps

from .audio_buffer import AudioBuffer
from .voice_detector import VoiceDetector, VADEvent
from .vad_manager import VADManager,VADSegment
from .sense_voice import SenseVoiceSTT
from .speaker import Speaker
from config.config_manager import config
from tools.bin_tools import ndarray_to_audio_frame
from tools.text_splitter import split_text, Token

logger = logging.getLogger(__name__)

def with_vad_lock(lock_type: str):
    """VAD事件处理锁装饰器
    Args:
        lock_type: 锁类型 ('long' 或 'short')
    """
    def decorator(func):
        @wraps(func)
        async def wrapper(self, *args, **kwargs):
            lock = self.long_vad_lock if lock_type == 'long' else self.short_vad_lock
            async with lock:
                return await func(self, *args, **kwargs)
        return wrapper
    return decorator

class AudioProcessor:
    """音频处理主模块"""
    
    def __init__(self):
        """初始化音频处理器"""
        # 加载配置
        self.cfg = config
        
        # 初始化核心组件
        self.voice_detector = VoiceDetector()
        self.speaker_detector = Speaker()
        self.asr = SenseVoiceSTT(use_onnx=self.cfg.audio_config['asr']['use_onnx'])
        
        # 初始化音频缓冲区
        buffer_cfg = self.cfg.buffer_config
        self.audio_buffer = AudioBuffer(
            max_duration=buffer_cfg['long_buffer_duration']
        )
        
        # 初始化VAD管理器
        self.vad_manager = VADManager()
        
        # 事件队列
        self.event_queue = asyncio.Queue(
            maxsize=self.cfg.get('events.max_queue_size', 1000)
        )
        
        # 处理状态
        self.is_processing = False  # 初始化时不启动处理
        self.last_process_time = 0.0
        self.current_speaker_id: Optional[str] = None
        
        # 清理任务
        self.cleanup_task: Optional[asyncio.Task] = None
        
        # 添加处理时间跟踪
        self.last_long_process_time: Optional[float] = None
        self.speech_start_time: Optional[float] = None
        
        # VAD 处理状态
        self.current_vad_start: Optional[float] = None  # 当前 VAD 段的开始时间
        self.last_process_end: Optional[float] = None   # 上次处理的结束时间
        self.is_speaking = False                        # 当前是否在说话
        self.current_long_segment = None  # 用于管理长VAD段
        self.last_short_vad_end = None   # 上一次短VAD事件的结束时间
        
        # 说话人合并阈值（基于基础阈值调整）
        self.speaker_merge_threshold = self.cfg.speaker.get('threshold', {}).get('base', 0.25) * 1.25
        
        # 分别为长段和短段处理添加锁
        self.long_vad_lock = asyncio.Lock()  # 用于长段处理（speech_start/long_pause）
        self.short_vad_lock = asyncio.Lock() # 用于短段处理（short_pause）
        
    async def start(self):
        """启动处理器"""
        if not self.is_processing:
            self.is_processing = True
            # 启动清理任务
            self.cleanup_task = asyncio.create_task(self._cleanup_loop())
            logger.info("Audio processor started")
            
    async def stop(self):
        """停止处理器"""
        if self.is_processing:
            self.is_processing = False
            if self.cleanup_task:
                self.cleanup_task.cancel()
                try:
                    await self.cleanup_task
                except asyncio.CancelledError:
                    pass
            # 清理资源
            self.audio_buffer.clear()
            logger.info("Audio processor stopped")
        
    async def process_audio(self, audio_data: np.ndarray, timestamp: float) -> None:
        """处理音频数据
        
        Args:
            audio_data: 音频数据 (int16 格式)
            timestamp: 客户端传来的音频终止时间戳
        """
        if not self.is_processing:
            return
            
        # 检查输入格式
        if audio_data.dtype != np.int16:
            raise ValueError(f"Expected int16 audio data, got {audio_data.dtype}")
        
        # 检查音频长度
        frame_duration = len(audio_data) / self.cfg.audio_config['sample_rate']
        if frame_duration > 0.2:
            logger.warning(f"Audio frame too long: {frame_duration*1000:.1f}ms")
        elif frame_duration < 0.01:
            logger.warning(f"Audio frame too short: {frame_duration*1000:.1f}ms")
        
        # 更新缓冲区
        self.audio_buffer.write(audio_data, frame_duration, timestamp)
        
        # VAD 检测 (VAD需要float32格式)
        audio_float = self.audio_buffer._int16_to_float32(audio_data)
        event = await self.voice_detector.process_frame(audio_float, timestamp)
        if not event:
            return
            
        logger.info(f"Processing VAD event: {event.value}")
        
        if event == VADEvent.SPEECH_START:
            # 开始新的长段
            await self._update_long_segment('start', timestamp, frame_duration)
            self.last_short_vad_end = None  # 重置短VAD结束时间
            
        elif event == VADEvent.SHORT_PAUSE or event == VADEvent.SHORT_TIMEOUT:
            if self.cfg.vad_config['enable_quick']:
                # 确定起始时间
                if self.last_short_vad_end is None and self.current_long_segment:
                    # 长段内的第一次短VAD
                    start_time = self.current_long_segment['start_time']
                else:
                    # 后续的短VAD
                    start_time = self.last_short_vad_end or (timestamp - frame_duration)
                if event == VADEvent.SHORT_TIMEOUT and not self.cfg.vad_config['enable_quick_timeout']:
                    logger.debug('skip VADEvent.SHORT_TIMEOUT')
                    return
                await self._handle_short_vad(event, start_time, timestamp)
                if event == VADEvent.SHORT_PAUSE:
                    self.last_short_vad_end = timestamp  # 更新短VAD结束时间
                else:
                    pass # 从短暂停开始重新识别，提高准确率
            
        elif event == VADEvent.LONG_TIMEOUT:
            pass # 暂时不用

        elif event == VADEvent.LONG_PAUSE:
            # 结束当前长段
            await self._update_long_segment('end', timestamp)
            self.last_short_vad_end = None  # 重置短VAD结束时间
            
    async def _process_segment(self, start_time: float, end_time: float, is_final: bool = False):
        """处理音频片段的核心逻辑"""
        try:
            audio_data, actual_start, actual_end = self.audio_buffer.read(start_time, end_time)
            if len(audio_data) < 100: return
            return await self._process_audio_core(
                audio_data=audio_data,
                start_time=actual_start,
                end_time=actual_end,
                is_final=is_final
            )
        except Exception as e:
            logger.error(f"Error processing segment: {str(e)}", exc_info=True)

    async def _process_audio_core(self, audio_data: np.ndarray, start_time: float, end_time: float, is_final: bool):
        """音频处理核心逻辑（可复用部分）"""
        
        logger.debug(f"get_speakerid_from_buffer_async from _process_audio_core, audio : {start_time:.3f} -> {end_time:.3f}")
        speaker_task = self.speaker_detector.get_speakerid_from_buffer_async(
            audio_data, 
            self.cfg.audio_config['sample_rate'],
            allow_update=False
        )
        
        # ASR保持使用原始int16格式
        audio_frame = ndarray_to_audio_frame(audio_data, self.cfg.audio_config['sample_rate'])
        asr_task = self.asr.recognize(
            buffer=audio_frame,  # int16格式
            language=self.cfg.audio_config['asr']['language'],
            output_timestamp=True
        )
        
        speaker_id, asr_result = await asyncio.gather(speaker_task, asr_task)
        
        # 发送结果并更新状态
        await self._send_transcription_result(
            start_time=start_time,
            end_time=end_time,
            speaker_id=speaker_id,
            asr_result=asr_result,
            is_final=is_final
        )
        return speaker_id

    async def _send_transcription_result(
        self,
        start_time: float,
        end_time: float,
        speaker_id: str,
        asr_result: Any,
        is_final: bool
    ):
        """统一发送识别结果"""
        text_content = asr_result.text if asr_result else ''
        if text_content:
            await self.event_queue.put({
                'type': 'transcription',
                'text': text_content,
                'speaker_id': speaker_id or '',
                'start_time': start_time,
                'end_time': end_time,
                'isFinal': is_final,
                'timestamp': getattr(asr_result, 'timestamp', [])
            })
            logger.info(f"Sent {'final' if is_final else 'partial'} result: {start_time:.3f}-{end_time:.3f}")
            
        # 更新当前说话人
        if speaker_id and speaker_id != self.current_speaker_id:
            self.current_speaker_id = speaker_id
            logger.info(f"Speaker changed to: {speaker_id}")

    async def _cleanup_loop(self) -> None:
        """定期清理过期数据"""
        while self.is_processing:
            try:
                current_time = time.time()
                
                # 1. 清理过期的VAD片段
                self.vad_manager.cleanup_old_segments(
                    current_time - self.cfg.buffer_config['long_buffer_duration']
                )
                
                # 2. 检查并记录缓冲区状态
                buffer_stats = self.audio_buffer.get_stats()
                if buffer_stats['total_duration'] > self.cfg.buffer_config['long_buffer_duration']:
                    logger.warning(
                        f"Buffer too large: {buffer_stats['total_duration']:.1f}s, "
                        f"{buffer_stats['frame_count']} frames, "
                        f"{buffer_stats['memory_usage']/1024/1024:.1f}MB"
                    )
                
                # 3. 强制清理
                self.audio_buffer._cleanup()
                
                # 4. 记录清理后的状态
                after_stats = self.audio_buffer.get_stats()
                if after_stats['frame_count'] < buffer_stats['frame_count']:
                    logger.info(
                        f"Cleaned up buffer: {buffer_stats['frame_count']} -> "
                        f"{after_stats['frame_count']} frames"
                    )
                
                # 5. 等待下一次清理
                await asyncio.sleep(self.cfg.vad_manager_config['cleanup_interval'])
                
            except Exception as e:
                logger.error(f"Cleanup error: {str(e)}")
                await asyncio.sleep(60)  # 错误后等待较长时间
                
    async def get_next_event(self) -> Dict[str, Any]:
        """获取下一个事件"""
        return await self.event_queue.get()
        
    def stop(self) -> None:
        """停止处理"""
        self.is_processing = False
        self.cleanup_task.cancel()
        # 清理资源
        self.audio_buffer.clear()
        
    @with_vad_lock('short')
    async def _handle_short_vad(self, event_type: VADEvent, start_time: float, end_time: float):
        """统一处理SHORT_PAUSE和SHORT_TIMEOUT
        
        注意：这里的时间是当前短片段的时间，与长段管理无关
        """
        try:
            # 1. 获取音频数据
            audio_data, actual_start, actual_end = self.audio_buffer.read(start_time, end_time)
            if len(audio_data) < 100:
                logger.warning(f"No audio data available for short VAD: {start_time:.3f} -> {end_time:.3f}")
                return
            logger.info(f"handle short vad: {start_time:.3f} -> {end_time:.3f}, event_type: {event_type.value}, audio_data: {len(audio_data)}")
            
            # 2. 并行处理ASR和Speaker
            audio_frame = ndarray_to_audio_frame(audio_data, self.cfg.audio_config['sample_rate'])

            logger.debug(f"get_speakerid_from_buffer_async from _handle_short_vad, audio : {start_time:.3f} -> {end_time:.3f}")
            speaker_task = self.speaker_detector.get_speakerid_from_buffer_async(audio_data, self.cfg.audio_config['sample_rate'], allow_update=False)
            asr_task = self.asr.recognize(buffer=audio_frame, language=self.cfg.audio_config['asr']['language'], output_timestamp=True)
            
            speaker_id, asr_result = await asyncio.gather(speaker_task, asr_task)
            
            # 3. 记录短段信息
            current_segment = VADSegment(
                event_type=event_type,
                start_time=start_time,
                end_time=end_time
            )
            if asr_result:
                # 取出开始时间戳 ms [[0, 210], [210, 390] ...]
                timestamps = [t[0] for t  in asr_result.timestamp ]
                current_segment.update_recognition(speaker_id, asr_result.text, timestamps=timestamps)
            self.vad_manager.add_segment(current_segment)
            
            # 4. 发送结果给客户端
            if asr_result:
                await self.event_queue.put({
                    'type': 'transcription',
                    'text': asr_result.text,
                    'speaker_id': speaker_id or '',
                    'start_time': actual_start,
                    'end_time': actual_end,
                    'isFinal': False,
                    'timestamp': asr_result.timestamp
                })
            
            # 5. 如果是SHORT_TIMEOUT，检查说话人切换
            # if event_type == VADEvent.SHORT_TIMEOUT:
            #     await self._check_speaker_switch()
                
        except Exception as e:
            logger.error(f"Error handling short VAD: {str(e)}", exc_info=True)
        
    async def _check_speaker_switch(self):
        """检查并处理说话人切换，基于声纹距离的三阶段判断"""
        try:
            # 1. 获取最近三个 VAD 段并进行初步判断
            recent_segments = self.vad_manager.get_recent_segments(3)
            if len(recent_segments) < 3:
                return
            
            n_minus_2 = recent_segments[-3]  # 第一段
            n_minus_1 = recent_segments[-2]  # 中间段待切分
            n = recent_segments[-1]          # 第三段

            # 2. 计算三段之间的声纹距离关系
            # 2.1 计算第一段和第三段之间的距离
            original_distance = self.speaker_detector.calculate_segment_distance(
                self.audio_buffer.read(n_minus_2.start_time, n_minus_2.end_time)[0],
                self.audio_buffer.read(n.start_time, n.end_time)[0],
                self.cfg.audio_config['sample_rate']
            )

            # 如果原始距离太小，表示前后段之间没有明显变化，不需要拆分
            if original_distance < self.speaker_merge_threshold:
                logger.debug(f"Original distance {original_distance:.3f} too small, skip splitting")
                return

            # 2.2 计算中间段与前后段的距离
            distance_with_prev = self.speaker_detector.calculate_segment_distance(
                self.audio_buffer.read(n_minus_2.start_time, n_minus_2.end_time)[0],
                self.audio_buffer.read(n_minus_1.start_time, n_minus_1.end_time)[0],
                self.cfg.audio_config['sample_rate']
            )
            
            distance_with_next = self.speaker_detector.calculate_segment_distance(
                self.audio_buffer.read(n_minus_1.start_time, n_minus_1.end_time)[0],
                self.audio_buffer.read(n.start_time, n.end_time)[0],
                self.cfg.audio_config['sample_rate']
            )

            # 2.3 验证中间段是否需要切分
            # 如果中间段与前后段的距离都大于原始距离，说明可能不是在中间段发生的变化
            if distance_with_prev >= original_distance and distance_with_next >= original_distance:
                logger.debug(f"Middle segment distances ({distance_with_prev:.3f}, {distance_with_next:.3f}) "
                           f"both larger than original distance {original_distance:.3f}, skip splitting")
                return

            # 3. 在ASR时间戳中寻找最佳切分点
            best_split = None
            min_combined_distance = float('inf')
            best_distances = None

            # 遍历ASR时间戳寻找最佳切分点
            check_point_count = 0
            for ts in n_minus_1.asr_timestamps:
                if ts < 100:  # 跳过太短的时间戳
                    continue
                check_point_count += 1
                split_time = n_minus_1.start_time + ts / 1000.0
                
                # 切分中间段
                part1 = self.audio_buffer.read(n_minus_1.start_time, split_time)[0]
                part2 = self.audio_buffer.read(split_time, n_minus_1.end_time)[0]
                
                # 计算切分后的距离
                distance1 = self.speaker_detector.calculate_segment_distance(
                    self.audio_buffer.read(n_minus_2.start_time, n_minus_2.end_time)[0],
                    part1,
                    self.cfg.audio_config['sample_rate']
                )
                distance2 = self.speaker_detector.calculate_segment_distance(
                    part2,
                    self.audio_buffer.read(n.start_time, n.end_time)[0],
                    self.cfg.audio_config['sample_rate']
                )
                
                # 计算组合距离
                combined_distance = (distance1 + distance2) / 2.0
                
                # 验证切分效果：
                # 1. 切分后的两部分都要比原始距离小
                # 2. 两部分之间的距离差异不能太大
                if (distance1 < original_distance and 
                    distance2 < original_distance and 
                    abs(distance1 - distance2) <= 0.2 * original_distance and 
                    combined_distance < min_combined_distance):
                    min_combined_distance = combined_distance
                    best_split = split_time
                    best_distances = (distance1, distance2)

            # 4. 执行切分
            if (best_split and 
                min_combined_distance < original_distance * 0.8):  # 要求明显改善
                logger.info(f"----____---- Found valid split point at {best_split:.3f}, check_point_count: {check_point_count},"
                          f"original_distance={original_distance:.3f}, "
                          f"new_distances=({best_distances[0]:.3f}, {best_distances[1]:.3f})")
                
                # 重新处理从原long段起点到切分点的音频
                original_start = self.current_long_segment['start_time']
                await self._process_segment(original_start, best_split, is_final=True)
                
                # 更新长段信息
                await self._update_long_segment('update', best_split)
            else:
                logger.debug(f"No valid split point found, best_split: {best_split}, min_combined_distance: {min_combined_distance},"
                             f" original_distance: {original_distance}, check_point_count: {check_point_count}, skip splitting")

        except Exception as e:
            logger.error(f"Error checking speaker switch: {str(e)}", exc_info=True)
        

    @with_vad_lock('long')
    async def _update_long_segment(self, action: str, timestamp: float = None, frame_duration: float = None):
        """管理长VAD段的状态
        
        Args:
            action: 操作类型
                - 'start': 开始新的长段
                - 'update': 更新当前长段
                - 'end': 结束当前长段
            timestamp: 当前时间戳
            frame_duration: 帧持续时间
        """
        if action == 'start':
            start_time = timestamp - frame_duration * 2  # 向前偏移n帧
            self.current_long_segment = {
                'start_time': start_time,  # 只保留起始时间
            }
            logger.info(f"Long segment started at {timestamp:.3f}, segment start at {start_time:.3f}")
            
        elif action == 'end':
            if self.current_long_segment:
                # 读取长段音频时获取实际时间
                long_audio, actual_segment_start, actual_segment_end = self.audio_buffer.read(
                    self.current_long_segment['start_time'],
                    timestamp
                )
                actual_duration = actual_segment_end - actual_segment_start
                logger.info(f"Long segment ended at {timestamp:.3f}, actual_duration: {actual_duration:.3f}")
                
                # 2. 利用 ASR 完整识别长段
                asr_result = await self.asr.recognize(
                    buffer=ndarray_to_audio_frame(long_audio, self.cfg.audio_config['sample_rate']),
                    language=self.cfg.audio_config['asr']['language'],
                    output_timestamp=True
                )
                
                # 检查ASR结果有效性
                if (not asr_result or not asr_result.text or 
                    actual_duration < self.cfg.audio_config['sentence_split']['min_duration_for_split'] or
                    not self.cfg.audio_config['sentence_split']['enable']):
                    logger.info("ASR result empty, or duration too short, fallback to processing whole segment")
                    # 直接使用整个长段的ASR结果和说话人识别
                    speaker_id = await self.speaker_detector.get_speakerid_from_buffer_async(
                        long_audio,
                        self.cfg.audio_config['sample_rate'],
                        allow_update=True
                    )
                    logger.debug(f"get_speakerid_from_buffer_async when duration too short, audio : {actual_segment_start:.3f} -> {actual_segment_end:.3f}, speaker_id: {speaker_id}")
                    await self._send_transcription_result(
                        start_time=actual_segment_start,
                        end_time=actual_segment_end,
                        speaker_id=speaker_id,
                        asr_result=asr_result,
                        is_final=True
                    )
                    logger.info(
                        f"Processed whole segment cause asr result empty: {actual_segment_start:.3f}->{actual_segment_end:.3f} "
                        f"speaker:{speaker_id} text:{asr_result.text[:50]}..."
                    )
                    self.current_long_segment = None
                    self.last_process_end = timestamp
                    return
                
                # 分割句子时使用实际时间基准
                sentences_with_ts = self._split_sentences_with_timestamps(
                    asr_result.text,
                    asr_result.timestamp,
                    actual_segment_start  # 使用实际读取的起始时间
                )
                
                # 处理分割失败的情况
                if not sentences_with_ts:
                    logger.warning("Sentence splitting failed, fallback to processing whole segment")
                    # 直接使用整个长段的ASR结果和说话人识别
                    speaker_id = await self.speaker_detector.get_speakerid_from_buffer_async(
                        long_audio,
                        self.cfg.audio_config['sample_rate'],
                        allow_update=True
                    )
                    logger.debug(f"get_speakerid_from_buffer_async when sentence splitting failed, audio : {actual_segment_start:.3f} -> {actual_segment_end:.3f}, speaker_id: {speaker_id}")
                    await self._send_transcription_result(
                        start_time=actual_segment_start,
                        end_time=actual_segment_end,
                        speaker_id=speaker_id,
                        asr_result=asr_result,
                        is_final=True,
                    )
                    logger.info(
                        f"Processed whole segment cause sentence splitting failed: {actual_segment_start:.3f}->{actual_segment_end:.3f} "
                        f"speaker:{speaker_id} text:{asr_result.text[:50]}..."
                    )
                    self.current_long_segment = None
                    self.last_process_end = timestamp
                    return
                
                # 4. 处理合并后的段落
                merged_segments = []
                current_start = None
                current_text = []
                current_ref_audio = None  # 用局部变量保存上一句话的音频作为参考
                speaker_ids = []  # 存储初步识别的说话人ID
                
                for sent_text, (sent_start, sent_end), timestamps in sentences_with_ts:
                    # 读取句子音频
                    sent_audio = self.audio_buffer.read(sent_start, sent_end)[0]
                    
                    # 使用上一句的音频作为参考计算距离
                    if current_ref_audio is not None:
                        try:
                            distance = self.speaker_detector.calculate_segment_distance(
                                sent_audio,  # 当前句子音频
                                current_ref_audio,  # 上一句的音频
                                self.cfg.audio_config['sample_rate']
                            )
                            # 处理无效距离（极大值时跳过切换）
                            if distance >= 10.0:
                                logger.warning("Invalid distance detected, skip speaker change")
                                distance = 0.0  # 视为相同说话人
                        except Exception as e:
                            logger.error(f"Error calculating distance: {e}")
                            distance = float('inf')
                    else:
                        distance = 1.0
                    
                    # 首次识别或距离超过阈值时创建新段
                    if current_start is None or distance > self.speaker_merge_threshold:
                        if current_start is not None:
                            merged_segments.append((
                                current_start,
                                sent_start,  # 使用下一句的开始作为当前段结束
                                ' '.join(current_text)
                            ))
                        # 保存当前音频作为下一次比较的参考
                        current_ref_audio = sent_audio
                        current_start = sent_start
                        current_text = [sent_text]
                    else:
                        current_text.append(sent_text)
                        # 更新参考音频为当前句子
                        current_ref_audio = sent_audio
                    # 取最后 10 S 的音频作为参考
                    if len(current_ref_audio) > 10 * self.cfg.audio_config['sample_rate']:
                        current_ref_audio = current_ref_audio[-10 * self.cfg.audio_config['sample_rate']:]
                
                # 添加最后一个段
                if current_start is not None:
                    merged_segments.append((
                        current_start,
                        timestamp,
                        ' '.join(current_text)  # 这里保存合并后的文本
                    ))
                
                # 第一步：初步识别所有段落的speaker_id
                for seg_start, seg_end, text in merged_segments:
                    sent_audio = self.audio_buffer.read(seg_start, seg_end)[0]
                    speaker_id = await self.speaker_detector.get_speakerid_from_buffer_async(
                        sent_audio, self.cfg.audio_config['sample_rate'],
                        allow_update=True
                    )
                    speaker_ids.append(speaker_id)
                    logger.debug(f"Preliminary speaker ID for {seg_start:.3f}-{seg_end:.3f}: {speaker_id}")
                
                # 第二步：处理speaker_id=0的情况
                for i in range(len(speaker_ids)):
                    if speaker_ids[i] != 0:
                        continue
                    
                    # 获取相邻段落信息
                    prev_id = speaker_ids[i-1] if i > 0 else None
                    next_id = speaker_ids[i+1] if i < len(speaker_ids)-1 else None
                    
                    # 读取当前段落音频
                    seg = merged_segments[i]
                    current_audio = self.audio_buffer.read(seg[0], seg[1])[0]
                    
                    # 计算距离
                    distances = {}
                    if prev_id is not None:
                        prev_audio = self.audio_buffer.read(merged_segments[i-1][0], merged_segments[i-1][1])[0]
                        distances[prev_id] = self.speaker_detector.calculate_segment_distance(
                            current_audio, prev_audio, self.cfg.audio_config['sample_rate']
                        )
                    if next_id is not None:
                        next_audio = self.audio_buffer.read(merged_segments[i+1][0], merged_segments[i+1][1])[0]
                        distances[next_id] = self.speaker_detector.calculate_segment_distance(
                            current_audio, next_audio, self.cfg.audio_config['sample_rate']
                        )
                    
                    # 选择最小距离的speaker_id
                    if distances:
                        min_id = min(distances, key=distances.get)
                        speaker_ids[i] = min_id
                        logger.info(f"Adjusted speaker ID for segment {i} from 0 to {min_id} based on distance")
                    else:
                        # 没有相邻有效段落，保持0
                        logger.warning(f"Cannot adjust speaker ID for isolated segment {i}")
                
                # 第三步：发送最终结果
                for idx, (seg_start, seg_end, text) in enumerate(merged_segments):
                    speaker_id = speaker_ids[idx]
                    # 从原始ASR结果中提取对应时间范围的时间戳
                    segment_timestamps = [
                        ts for ts in asr_result.timestamp 
                        if (seg_start - actual_segment_start) * 1000 <= ts[0] and 
                           ts[1] <= (seg_end - actual_segment_start) * 1000
                    ]
                    
                    # 调整时间戳的基准时间
                    adjusted_timestamps = [
                        [ts[0] - int((seg_start - actual_segment_start) * 1000),
                         ts[1] - int((seg_start - actual_segment_start) * 1000)]
                        for ts in segment_timestamps
                    ]
                    
                    await self._send_transcription_result(
                        start_time=seg_start,
                        end_time=seg_end,
                        speaker_id=speaker_id or '',
                        asr_result=type('', (), {
                            'text': text, 
                            'timestamp': adjusted_timestamps
                        })(),
                        is_final=True
                    )
                    logger.info(f"Merged segment: {seg_start:.3f}-{seg_end:.3f} speaker:{speaker_id}")
                
                self.current_long_segment = None
                self.last_process_end = timestamp
                logger.info(f"Processed long segment, split into {len(merged_segments)} segments")
                
        elif action == 'update':
            if timestamp and self.current_long_segment:
                self.current_long_segment['start_time'] = timestamp
                logger.debug(f"Long segment updated, new start time: {timestamp:.3f}")

    def _split_sentences_with_timestamps(
        self,
        text: str,
        timestamps: List[List[int]],
        audio_start: float
    ) -> List[Tuple[str, Tuple[float, float], List[List[int]]]]:
        """将ASR结果按标点分割为带时间戳的句子
        
        Returns:
            List[Tuple[str, Tuple[float, float], List[List[int]]]]: [(句子文本, (开始时间, 结束时间), token时间戳列表), ...]
        """
        
        # 1. 分割文本为token
        tokens = split_text(text)
        # 允许token和timestamps数量有轻微差异
        if abs(len(tokens) - len(timestamps)) > 1:
            logger.warning(f"Token count mismatch too large: text tokens {len(tokens)} vs timestamps {len(timestamps)}")
            return []
        elif len(tokens) != len(timestamps):
            logger.info(f"Minor token count mismatch: text tokens {len(tokens)} vs timestamps {len(timestamps)}, continuing with shorter length")
            # 使用较短的长度进行处理
            min_length = min(len(tokens), len(timestamps))
            tokens = tokens[:min_length]
            timestamps = timestamps[:min_length]
        
        # 获取最小句子时长配置
        min_sentence_duration = self.cfg.speaker.get('min_chunk_duration', 3.0)
        
        # 2. 查找句子边界
        sentences = []
        current_sentence = []
        current_timestamps = []
        pending_sentence = None  # 用于存储待合并的短句
        
        for token, ts in zip(tokens, timestamps):
            # 根据token类型决定是否添加空格
            if current_sentence and token.is_english_word and current_sentence[-1].is_english_word:
                current_sentence.append(Token(' ', False, False, False))
                current_timestamps.append(ts)
            current_sentence.append(token)
            current_timestamps.append(ts)
            
            # 检查是否为句子结束标点
            if token.is_punctuation and token.text in {'。', '！', '？', '!', '?'}:
                # 计算句子时间边界
                start_time = audio_start + current_timestamps[0][0] / 1000.0
                end_time = audio_start + current_timestamps[-1][1] / 1000.0
                duration = end_time - start_time
                
                # 合并token时考虑token类型
                sentence_text = ''.join(t.text for t in current_sentence).strip()
                current_sentence_info = (sentence_text, (start_time, end_time), current_timestamps)
                
                # 处理短句合并逻辑
                if duration < min_sentence_duration:
                    if pending_sentence is None:
                        pending_sentence = current_sentence_info
                    else:
                        # 合并待合并句子和当前句子
                        merged_text = pending_sentence[0] + sentence_text
                        merged_start = pending_sentence[1][0]
                        merged_timestamps = pending_sentence[2] + current_timestamps
                        
                        if end_time - merged_start >= min_sentence_duration:
                            # 合并后长度足够，添加到结果中
                            sentences.append((merged_text, (merged_start, end_time), merged_timestamps))
                            pending_sentence = None
                        else:
                            # 合并后仍然太短，继续等待下一句
                            pending_sentence = (merged_text, (merged_start, end_time), merged_timestamps)
                else:
                    # 当前句子长度足够
                    if pending_sentence is not None:
                        sentences.append(pending_sentence)
                        pending_sentence = None
                    sentences.append(current_sentence_info)
                
                current_sentence = []
                current_timestamps = []
        
        # 处理剩余内容
        if current_sentence:
            start_time = audio_start + current_timestamps[0][0] / 1000.0
            end_time = audio_start + current_timestamps[-1][1] / 1000.0
            sentence_text = ''.join(t.text for t in current_sentence).strip()
            current_sentence_info = (sentence_text, (start_time, end_time), current_timestamps)
            duration = end_time - start_time
            
            # 如果剩余句子持续时间过短，不单独划分出来
            if duration < min_sentence_duration:
                if sentences:
                    # 将短句合并到前面已输出的最后一句中
                    prev_sentence = sentences.pop()
                    merged_text = prev_sentence[0] + current_sentence_info[0]
                    merged_start = prev_sentence[1][0]
                    merged_end = current_sentence_info[1][1]
                    merged_timestamps = prev_sentence[2] + current_sentence_info[2]
                    sentences.append((merged_text, (merged_start, merged_end), merged_timestamps))
                elif pending_sentence is not None:
                    merged_text = pending_sentence[0] + current_sentence_info[0]
                    merged_start = pending_sentence[1][0]
                    merged_timestamps = pending_sentence[2] + current_sentence_info[2]
                    sentences.append((merged_text, (merged_start, end_time), merged_timestamps))
                else:
                    # 没有前面的内容，则直接添加（尽管太短）
                    sentences.append(current_sentence_info)
            else:
                if pending_sentence is not None:
                    merged_text = pending_sentence[0] + current_sentence_info[0]
                    merged_start = pending_sentence[1][0]
                    merged_timestamps = pending_sentence[2] + current_sentence_info[2]
                    sentences.append((merged_text, (merged_start, end_time), merged_timestamps))
                else:
                    sentences.append(current_sentence_info)
        elif pending_sentence is not None:
            sentences.append(pending_sentence)
        
        return sentences

    async def force_process_pending(self):
        """Force process any pending audio segments when streaming stops"""
        try:
            if self.current_long_segment:
                logger.info("Force processing pending audio segment due to stream stop")
                current_time = time.time()
                await self._update_long_segment('end', current_time)
        except Exception as e:
            logger.error(f"Error force processing pending audio: {str(e)}", exc_info=True)