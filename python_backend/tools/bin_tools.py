import numpy as np
import torch
from livekit import rtc
# from memoryview to tensor
# buf: wave bytes
# is_2d: if True, return 2D tensor, otherwise return 1D tensor
def memoryview_to_tensor(buf,  is_2d=False):
    audio_data = np.frombuffer(buf, dtype=np.int16)
    audio_data = audio_data.astype(np.float32) / 32768.0
    if is_2d:
        audio_tensor = torch.from_numpy(audio_data.reshape(1, -1))
    else:
        audio_tensor = torch.from_numpy(audio_data)
    return audio_tensor

#from memoryview to np.ndarray
def memoryview_to_ndarray(buf, is_2d=False):
    audio_data = np.frombuffer(buf, dtype=np.int16)
    audio_data = audio_data.astype(np.float32) / 32768.0
    if is_2d:
        audio_data = audio_data.reshape(1, -1)
    return audio_data


# from np.ndarray to rtc.AudioFrame
def ndarray_to_audio_frame(audio_data: np.ndarray, sample_rate: int = 16000, num_channels: int = 1) -> rtc.AudioFrame:
    """将numpy数组转换为AudioFrame
    
    Args:
        audio_data: 音频数据 (int16 格式)
        sample_rate: 采样率，默认16000Hz
        num_channels: 通道数，默认1
        
    Returns:
        rtc.AudioFrame: 音频帧
    """
    if audio_data.dtype != np.int16:
        audio_data = (audio_data * 32768.0).astype(np.int16)
        
    return rtc.AudioFrame(
        data=audio_data.tobytes(),
        sample_rate=sample_rate,
        num_channels=num_channels,
        samples_per_channel=len(audio_data)
    )