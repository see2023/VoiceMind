import json
import numpy as np
import logging
import os
from typing import Dict, Optional
from pathlib import Path
import threading

class NumpyEncoder(json.JSONEncoder):
    """处理numpy数据类型的JSON编码器"""
    def default(self, obj):
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        if isinstance(obj, np.integer):
            return int(obj)
        if isinstance(obj, np.floating):
            return float(obj)
        return super().default(obj)

class SpeakerStorage:
    """Speaker embedding storage using JSON file"""
    
    def __init__(self, storage_path: str):
        self.storage_path = storage_path
        self.speakers: Dict[str, Dict] = {}
        self._lock = threading.Lock()
        self._ensure_storage_dir()
        self._load_speakers()  # Only load if file exists
        
    def _ensure_storage_dir(self):
        """Ensure storage directory exists"""
        os.makedirs(os.path.dirname(self.storage_path), exist_ok=True)
        
    def _load_speakers(self):
        """Load speakers from storage file if it exists"""
        if not os.path.exists(self.storage_path):
            logging.info(f"No speaker storage file found at {self.storage_path}")
            return
            
        try:
            with self._lock:
                with open(self.storage_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
            # Convert string arrays back to numpy arrays
            for speaker_id, speaker_data in data.items():
                embeddings = speaker_data['embeddings']
                speaker_data['embeddings'] = [
                    {
                        'duration': float(e['duration']),
                        'embedding': np.array(e['embedding'], dtype=np.float32)
                    }
                    for e in embeddings
                ]
                if 'average_embedding' in speaker_data:
                    speaker_data['average_embedding'] = np.array(
                        speaker_data['average_embedding'], 
                        dtype=np.float32
                    )
                speaker_data['average_distance'] = float(speaker_data['average_distance'])
                speaker_data['adaptive_threshold'] = float(speaker_data.get('adaptive_threshold', 0.25))
                self.speakers[speaker_id] = speaker_data
                
            logging.info(f"Loaded {len(self.speakers)} speakers from storage")
        except Exception as e:
            logging.error(f"Failed to load speakers: {e}", exc_info=True)
            
    def _save_speakers(self):
        """Save speakers to storage file"""
        try:
            with self._lock:
                # 创建临时文件
                temp_path = f"{self.storage_path}.tmp"
                with open(temp_path, 'w', encoding='utf-8') as f:
                    json.dump(
                        self.speakers,
                        f,
                        cls=NumpyEncoder,
                        ensure_ascii=False,
                        indent=2  # 美化输出
                    )
                
                # 原子性地替换文件
                os.replace(temp_path, self.storage_path)
                
            logging.info(f"Saved {len(self.speakers)} speakers to storage")
        except Exception as e:
            logging.error(f"Failed to save speakers: {e}", exc_info=True)
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except:
                    pass
            
    def add_or_update_speaker(self, speaker_id: str, speaker_data: Dict):
        """Add new speaker or update existing speaker data"""
        try:
            is_new = speaker_id not in self.speakers
            self.speakers[speaker_id] = speaker_data
            self._save_speakers()
            
            if is_new:
                logging.info(f"Added new speaker {speaker_id} with {len(speaker_data['embeddings'])} embeddings")
            else:
                logging.info(f"Updated speaker {speaker_id} with {len(speaker_data['embeddings'])} embeddings")
            
        except Exception as e:
            logging.error(f"Failed to {'add' if is_new else 'update'} speaker {speaker_id}: {e}", exc_info=True)
            raise
        
    def get_speaker(self, speaker_id: str) -> Optional[Dict]:
        """Get speaker data by ID"""
        return self.speakers.get(speaker_id)
        
    def get_all_speakers(self) -> Dict[str, Dict]:
        """Get all speakers"""
        return self.speakers
        
    def remove_speaker(self, speaker_id: str):
        """Remove speaker by ID"""
        if speaker_id in self.speakers:
            del self.speakers[speaker_id]
            self._save_speakers()