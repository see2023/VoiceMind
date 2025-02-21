from dotenv import load_dotenv
load_dotenv()
import time
import torch
import numpy as np
from pyannote.audio import Model, Inference
from pyannote.core import Segment
from funasr.models.campplus.model import CAMPPlus
from huggingface_hub import hf_hub_download
from scipy.spatial.distance import cdist
import asyncio
import logging
from dataclasses import dataclass
from typing import List, Optional
from collections import deque
from tools.bin_tools import memoryview_to_tensor, memoryview_to_ndarray
from config.config_manager import config
from .speaker_storage import SpeakerStorage

logger = logging.getLogger(__name__)

@dataclass
class SpeakerEmbedding:
    duration:float
    embedding:np.ndarray


# 记录同一个人的多个音频embedding
class SpeakerEmbeddings:
    embeddings: List[SpeakerEmbedding]
    average_embedding:np.ndarray = None
    average_distance:float = 0.0
    id:int = 0

    def __init__(self, id:int, adaptive_threshold:float = 0.25):
        self.id = id
        self.max_embeddings = config.speaker['embedding']['max_embeddings']
        self.embeddings = []
        self.historical_distances = deque(maxlen=10)  # 保存最近10个距离值
        self.adaptive_threshold = adaptive_threshold

    def add_embedding(self, duration: float, embedding: np.ndarray):
        if len(self.embeddings) < self.max_embeddings:
            self.embeddings.append(SpeakerEmbedding(duration, embedding))
            logger.debug(f"Add new embedding with duration {duration} and shape {embedding.shape} for speaker {self.id}")
        else:
            # 计算新音频和现有音频的平均距离
            distances = []
            for e in self.embeddings:
                distances.append(cdist(embedding, e.embedding, metric="cosine")[0,0])
            average_distance = np.mean(distances)
            # 如果新音频距离平均距离小于当前平均距离，则替换掉最远的音频
            if average_distance < self.average_distance:
                max_index = np.argmax(distances)
                self.embeddings[max_index] = SpeakerEmbedding(duration, embedding)
                logger.debug(f"Replace embedding with duration {duration} and distance {average_distance} for speaker {self.id}, current average distance is {self.average_distance}")
            else:
                logger.debug(f"No replacement for speaker {self.id}, New embedding with duration {duration} and distance {average_distance} is far from average embedding with distance {self.average_distance}")
                return 
        self.update_average_embedding()

    def to_dict(self) -> dict:
        """Convert to storage format"""
        return {
            'embeddings': [
                {
                    'duration': float(e.duration),
                    'embedding': e.embedding.astype(np.float32)
                }
                for e in self.embeddings
            ],
            'average_embedding': self.average_embedding.astype(np.float32),
            'average_distance': float(self.average_distance),
            'adaptive_threshold': float(self.adaptive_threshold)
        }

    def update_average_embedding(self):
        if len(self.embeddings) == 0:
            return None
        # 取所有embedding的平均值作为最终的embedding
        embeddings = [e.embedding for e in self.embeddings]
        self.average_embedding = np.mean(embeddings, axis=0)
        # 计算所有embedding之间的平均距离
        if len(embeddings) == 1:
            self.average_distance = 0.0
            return
        distances = []
        for i in range(len(embeddings)):
            for j in range(i+1, len(embeddings)):
                distances.append(cdist(embeddings[i], embeddings[j], metric="cosine")[0,0])
        self.average_distance = np.mean(distances)
        logger.debug(f"Update average distance to {self.average_distance} for speaker {self.id}")

    def get_embedding(self):
        return self.average_embedding
    
    # 判断是否是同一个人的声音，如果是，则判断距离来更新embeddings
    def is_same_speaker(self, embedding:np.ndarray, base_threshold:float = 0.25, duration:float = 0.0, allow_update:bool = True):
        """判断是否是同一个人的声音
        
        Args:
            embedding: 待比较的embedding
            base_threshold: 基础阈值
            duration: 音频时长
            allow_update: 是否允许更新embedding
        """
        if self.average_embedding is None or duration < 0.1:
            return False, None
        
        distance = cdist(self.average_embedding, embedding, metric="cosine")[0,0]
        
        # 动态阈值调整
        duration_factor = 1
        if duration < 3.0:  # 短音频
        # 小幅增加阈值，最多增加25%
            duration_factor = 1 + min(0.25, (3.0 - duration) / 3.0 * 0.25)
        current_threshold = self.adaptive_threshold * duration_factor
        
        # 使用历史距离进行判断
        avg_historical = np.mean(self.historical_distances) if self.historical_distances else current_threshold
        std_historical = np.std(self.historical_distances) if len(self.historical_distances) > 1 else current_threshold * 0.1
        
        is_same = (distance < current_threshold or 
                   distance < avg_historical + std_historical)
        
        # logger.debug(f"Speaker {self.id} - Distance: {distance:.4f}, Threshold: {current_threshold:.4f}, "
        #               f"Avg Historical: {avg_historical:.4f}, Std Historical: {std_historical:.4f}, "
        #               f"Duration: {duration:.2f}s, Is Same: {is_same}, Allow Update: {allow_update}")
        
        if is_same and allow_update:
            self.add_embedding(duration, embedding)
            self.historical_distances.append(distance)
            # 更新自适应阈值
            self.adaptive_threshold = (self.adaptive_threshold * 0.9 + distance * 0.1)
        
        return is_same, distance
    
# https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM
class Speaker:
    """说话人识别模块
    
    输入要求：
    - 格式：float32
    - 范围：[-1, 1]
    - 采样率：16000Hz
    - 通道：单通道
    """
    def __init__(self):
        # 从配置获取参数
        speaker_config = config.speaker
        model_config = speaker_config['model']
        embedding_config = speaker_config['embedding']
        threshold_config = speaker_config['threshold']
        
        self.device = torch.device(model_config['device'])
        self.use_campplus = model_config['use_campplus']
        self.speaker_distance_threshold = threshold_config['base']
        self.min_chunk_duration = embedding_config['min_chunk_duration']
        self.max_chunk_duration = embedding_config['max_chunk_duration']
        
        # 初始化模型和其他属性
        try:
            if self.use_campplus:
                self.model = CAMPPlus()
                model_path = hf_hub_download(repo_id="funasr/campplus", filename="campplus_cn_common.bin")
                self.model.load_state_dict(torch.load(model_path, map_location=torch.device('cpu')))
                self.model.to(self.device)
                self.model.eval()
            else:
                self.model = Model.from_pretrained("pyannote/wespeaker-voxceleb-resnet34-LM")
                self.inference = Inference(self.model, window="whole")
                self.inference.to(self.device)
        except Exception as e:
            logger.error(f"Error loading model: {e}")
            exit()

        # 初始化基本属性
        self.speakers = {}
        self.last_speaker_id = 0
        self.recent_speakers = deque(maxlen=5)
        self.current_meeting_id = None
        self.storage = None
        logger.info(f"Speaker initialized with storage=None, use_campplus={self.use_campplus}, max_embeddings={config.speaker['embedding']['max_embeddings']}")
        

    def _ensure_storage(self):
        """确保存储已初始化"""
        if self.storage is None and self.current_meeting_id is not None:
            logger.info(f"Initializing storage for meeting {self.current_meeting_id}")
            self.storage = SpeakerStorage(f"data/speakers.{self.current_meeting_id}.json")

    async def switch_meeting(self, meeting_id: int):
        """Switch to a new meeting context"""
        try:
            logger.info(f"Switching to meeting {meeting_id}")
            
            # Clear current speakers cache
            self.speakers = {}
            self.last_speaker_id = 0
            self.recent_speakers.clear()
            
            # Update current meeting ID and initialize new storage
            self.current_meeting_id = meeting_id
            self.storage = SpeakerStorage(f"data/speakers.{meeting_id}.json")
            logger.info(f"Storage initialized for meeting {meeting_id}")
            
            # Load speakers for new meeting if file exists
            stored_speakers = self.storage.get_all_speakers()
            for speaker_id, speaker_data in stored_speakers.items():
                speaker = SpeakerEmbeddings(int(speaker_id), self.speaker_distance_threshold)
                for embedding_data in speaker_data['embeddings']:
                    speaker.add_embedding(
                        embedding_data['duration'],
                        embedding_data['embedding']
                    )
                self.speakers[int(speaker_id)] = speaker
                self.last_speaker_id = max(self.last_speaker_id, int(speaker_id))
            
            if stored_speakers:
                logger.info(f"Loaded {len(stored_speakers)} speakers for meeting {meeting_id}")
            else:
                logger.info(f"No existing speakers found for meeting {meeting_id}")
                
        except Exception as e:
            logger.error(f"Error switching meeting: {e}")
            raise

    def get_embedding_by_file(self, file_path:str) -> np.ndarray:
        if self.use_campplus:
            embedding = self.model.inference(file_path)
        else:
            embedding = self.inference(file_path)
            # numpy.ndarray (float32,256)
        embedding = embedding.reshape(1, -1)
        return embedding
    
    # {"waveform": array or tensor, "sample_rate": int}
    def get_embedding_from_buffer(self, buf, sample_rate:int):
        total_duration = len(buf) / sample_rate
        if total_duration < 0.1:  # 设置一个最小的有效时长，比如100ms
            logger.debug(f"Audio buffer too short: {total_duration:.2f}s")
            return None
        
        if self.use_campplus:
            audio_tensor = memoryview_to_ndarray(buf, is_2d=True)
            results, _ = self.model.inference(audio_tensor, device=self.device)
            embedding = results[0]["spk_embedding"]
            # torch.shape [n, 192], calculate mean of n
            embedding = embedding.mean(axis=0).detach().cpu().numpy()
        else:
            audio_tensor = memoryview_to_tensor(buf, is_2d=True)
            seg = Segment(0, min(total_duration, self.max_chunk_duration))
            embedding = self.inference.crop({"waveform": audio_tensor, "sample_rate": sample_rate}, chunk=seg)
            # embedding = embedding.detach().cpu().numpy()
        embedding = embedding.reshape(1, -1)
        
        # if total_duration < self.min_chunk_duration:
            # logger.debug(f"Audio duration ({total_duration:.2f}s) < min_chunk_duration ({self.min_chunk_duration:.2f}s), will not update embeddings")
        
        return embedding
    
    def calculate_segment_distance(self, seg1, seg2, sample_rate:int):
        """计算两个音频片段的距离（简化版）"""
        try:
            if seg1 is None or seg2 is None or len(seg1) == 0 or len(seg2) == 0:
                return float('inf')  # 返回极大值表示无效
            
            # 提取embedding
            embedding_1 = self.get_embedding_from_buffer(seg1, sample_rate)
            embedding_2 = self.get_embedding_from_buffer(seg2, sample_rate)
            
            if embedding_1 is None or embedding_2 is None:
                return float('inf')
            
            # 计算余弦距离
            return cdist(embedding_1, embedding_2, metric="cosine")[0,0]
            
        except Exception as e:
            logger.error(f"Distance calculation error: {e}")
            return float('inf')
    
    def write_to_wav(self, buf, sample_rate:int):
        # 用wav 写入 ./data/{timestamp}_{duration}.wav
        import wave
        timestamp = time.time()
        duration = len(buf) / sample_rate
        wav_path = f"./data/{timestamp}_{duration}.wav"
        wav_file = wave.open(wav_path, 'wb')
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        # 转换float32到int16
        if buf.dtype == np.float32:
            buf = (buf * 32767).astype(np.int16)
            logger.debug(f"write_to_wav: {wav_path}, buf.dtype: {buf.dtype}, buf.shape: {buf.shape}")
        else:
            logger.debug(f"write_to_wav: {wav_path}, buf.dtype: {buf.dtype}, buf.shape: {buf.shape}")
        wav_file.writeframes(buf)
        wav_file.close()
    
    def get_speakerid_from_buffer(self, buf, sample_rate:int, allow_update:bool = True):
        try:
            start_time = time.time()
            new_embedding = self.get_embedding_from_buffer(buf, sample_rate)
            total_duration = len(buf) / sample_rate
            if new_embedding is None:
                return 0
            
            # self.write_to_wav(buf, sample_rate)

            # 判断是否允许更新
            if total_duration < self.min_chunk_duration:
                allow_update = False

            if not self.speakers:
                # 时长不够不创建新说话人
                if not allow_update:
                    return 0
                return self._add_new_speaker(new_embedding, total_duration)

            # 首先检查最近的说话人
            for speaker_id in self.recent_speakers:
                rt, distance = self.speakers[speaker_id].is_same_speaker(
                    new_embedding, 
                    self.speaker_distance_threshold, 
                    total_duration,
                    allow_update
                )
                if rt:
                    if allow_update:
                        self._update_recent_speakers(speaker_id)
                        self._update_speaker_storage(speaker_id)
                    logger.info(f"Recent speaker found with id: {speaker_id}, time: {time.time() - start_time:.4f}s, distance: {distance:.4f}, duration: {total_duration:.3f}s")
                    return speaker_id
                else:
                    # logger.debug(f"Recent speaker not found with id: {speaker_id}, time: {time.time() - start_time:.4f}s, distance: {distance:.4f}, duration: {total_duration:.3f}s")
                    pass
            
            # 如果是短音频且没有找到完全匹配的说话人,从最近说话人中找最接近的
            if not allow_update:
                distances = []
                for recent_id in self.recent_speakers:
                    speaker = self.speakers[recent_id]
                    if speaker.get_embedding() is not None:
                        dist = cdist(new_embedding, speaker.get_embedding().reshape(1, -1), metric="cosine")[0,0]
                        distances.append((recent_id, dist))
                
                if distances:
                    # 找出距离最小的说话人
                    closest_speaker_id = min(distances, key=lambda x: x[1])[0]
                    logger.debug(f"Short audio: using closest recent speaker {closest_speaker_id}")
                    return closest_speaker_id
                return 0

            # 如果最近的说话人中没有匹配，检查所有说话人
            for speaker_id, speaker_embedding in self.speakers.items():
                rt, distance = speaker_embedding.is_same_speaker(
                    new_embedding, 
                    self.speaker_distance_threshold, 
                    total_duration,
                    allow_update
                )
                if rt:
                    if allow_update:
                        self._update_recent_speakers(speaker_id)
                        self._update_speaker_storage(speaker_id)
                    logger.info(f"Speaker found with id: {speaker_id}, time: {time.time() - start_time:.4f}s, distance: {distance:.4f}, duration: {total_duration:.3f}s")
                    return speaker_id

            return self._add_new_speaker(new_embedding, total_duration)

        except Exception as e:
            logger.error(f"Error getting speaker id from buffer: {e}")
            return 0

    def _add_new_speaker(self, embedding, duration):
        self.last_speaker_id += 1
        speaker = SpeakerEmbeddings(self.last_speaker_id, self.speaker_distance_threshold)
        speaker.add_embedding(duration, embedding)
        self.speakers[self.last_speaker_id] = speaker
        if not self.storage:
            logger.warning(f'_add_new_speaker meeting null storage, reinit with meeting id: {self.current_meeting_id} ')
            self._ensure_storage()
        
        try:
            self.storage.add_or_update_speaker(
                str(self.last_speaker_id), 
                speaker.to_dict()
            )
        except Exception as e:
            logger.error(f"Failed to save new speaker {self.last_speaker_id}: {e}")
        
        self._update_recent_speakers(self.last_speaker_id)
        return self.last_speaker_id

    def _update_recent_speakers(self, speaker_id):
        if speaker_id in self.recent_speakers:
            self.recent_speakers.remove(speaker_id)
        self.recent_speakers.appendleft(speaker_id)

    async def get_speakerid_from_buffer_async(self, buf, sample_rate:int, allow_update:bool = True):
        return await asyncio.get_event_loop().run_in_executor(None, self.get_speakerid_from_buffer, buf, sample_rate, allow_update)

    def get_distance_by_file(self, file_path_1:str, file_path_2:str):
        embedding_1 = self.get_embedding_by_file(file_path_1)
        embedding_2 = self.get_embedding_by_file(file_path_2)
        distance = cdist(embedding_1, embedding_2, metric="cosine")[0,0]
        return distance

    def _update_speaker_storage(self, speaker_id: int):
        """更新说话人存储"""
        try:
            speaker = self.speakers[speaker_id]
            self.storage.add_or_update_speaker(str(speaker_id), speaker.to_dict())
        except Exception as e:
            logger.error(f"Failed to update speaker {speaker_id}: {e}")

    def get_speaker_embedding(self, speaker_id: int) -> Optional[np.ndarray]:
        """获取指定说话人的平均embedding"""
        speaker = self.speakers.get(speaker_id)
        if speaker and speaker.average_embedding is not None:
            return speaker.average_embedding
        return None

def test_get_speaker_embedding():
    file_path_1 = 'output.wav'
    file_path_2 = 'output_local.wav'
    file_path_3 = '01.wav'
    file_path_4 = '02.wav'

    file_path_3 = 'records/2024-04-01-11-57-59.wav'
    file_path_4 = 'records/2024-04-01-11-58-10.wav'

    speaker = Speaker()
    start_time = time.time()
    distance = speaker.get_distance_by_file(file_path_1, file_path_2)
    logger.info(f'Distance between two embeddings: {distance:.4f}')
    end_time = time.time()
    logger.info(f"Time taken for inference: {end_time - start_time:.4f} seconds")
    start_time = time.time()
    distance = speaker.get_distance_by_file(file_path_3, file_path_4)
    logger.info(f'Distance between two embeddings: {distance:.4f}')
    end_time = time.time()
    logger.info(f"Time taken for inference: {end_time - start_time:.4f} seconds")





if __name__ == '__main__':
    logger.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s [in %(pathname)s:%(lineno)d] - %(message)s',
    )
    test_get_speaker_embedding()
