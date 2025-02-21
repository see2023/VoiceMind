from typing import Optional
from livekit import agents, rtc
from livekit.agents.utils import AudioBuffer
from livekit.agents import stt
import logging
import time
from .stt_base import MySpeechData
from tools.bin_tools import memoryview_to_tensor, memoryview_to_ndarray
from funasr_onnx import SenseVoiceSmall
from funasr import AutoModel
from funasr_onnx.utils.postprocess_utils import rich_transcription_postprocess

class SenseVoiceSTT(stt.STT):
    """语音识别模块
    
    输入要求：
    - 格式：int16
    - 范围：[-32768, 32767]
    - 采样率：16000Hz
    - 通道：单通道
    - 传入方式：rtc.AudioFrame
    """
    def __init__(self, *, streaming_supported: bool = False, use_onnx: bool = False) -> None:
        super().__init__(streaming_supported=streaming_supported)
        self.use_onnx = use_onnx

        # mps cuda cpu # 实测 mps 2.7 it/s, cpu 3.8 it/s, mps存在性能问题
        # mps  2.7.  it/s  0.233   0.246.     0.096     2.807 ?
        # cpu  3.80it/s   0.232(0.5) 0.24(0.33) 0.095(0.36) . # 前面为模型输出，括号内为日志相减
        # onnx  0.1  0.6  0.18
        # device = "mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu"
        model_dir = "iic/SenseVoiceSmall"
        if self.use_onnx:
            self.model = SenseVoiceSmall(model_dir, batch_size=10, quantize=False)
        else:
            self.model = AutoModel(model=model_dir, trust_remote_code=False, disable_update=True)
        logging.info("sense_voice stt init success")
    
    @classmethod
    def change_sample_rate(cls, buffer: AudioBuffer, sample_rate: int) -> AudioBuffer:
        if buffer.sample_rate == sample_rate:
            return buffer
        return buffer.remix_and_resample(sample_rate, buffer.num_channels)
    
    async def recognize(
        self,
        *,
        buffer: AudioBuffer,
        language: Optional[str] = None,
        output_timestamp: bool = True
    ) -> MySpeechData:
        buffer = self.change_sample_rate(buffer, 16000)
        buffer: rtc.AudioFrame = agents.utils.merge_frames(buffer)
        duration = len(buffer.data) / buffer.sample_rate
        now = time.time()
        speechData = MySpeechData(language=language or "zh", text='', start_time=now-duration, end_time=now)

        try:
            if self.use_onnx:
                input = memoryview_to_ndarray(buffer.data)
                res = self.model(input, language=language, use_itn=True)
                speechData.text = rich_transcription_postprocess(res[0])
            else:
                input = memoryview_to_tensor(buffer.data)
                res = self.model.generate(
                    input=input,
                    cache={},
                    language=language,  # "zn", "en", "yue", "ja", "ko", "nospeech", "auto"
                    use_itn=True,
                    output_timestamp=output_timestamp
                )
                speechData.text = rich_transcription_postprocess(res[0]["text"])
                if res[0]["timestamp"]:
                    speechData.timestamp = res[0]["timestamp"]
            logging.info(f"sense_voice recognize result:{speechData.text}, timestamp:{speechData.timestamp}")
        except Exception as e:
            logging.error("sense_voice recognize exception:", e)
        return speechData
    