from dataclasses import dataclass, field
from typing import List

@dataclass
class MySpeechData():
    language: str
    text: str
    start_time: float
    end_time: float
    confidence: float = 0.0
    speaker_id: str = ''
    timestamp: List[List[int]] = field(default_factory=list)  # in ms [[0, 210], [210, 390] ...]

    def update_speaker(self, speaker_id: str):
        self.speaker_id = speaker_id
        return self
