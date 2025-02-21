import pyaudio
import wave
import os
from datetime import datetime

class AudioRecorder:
    def __init__(self):
        self.CHUNK = 1024
        self.FORMAT = pyaudio.paInt16
        self.CHANNELS = 1
        self.RATE = 16000
        self.OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
        
        # 确保输出目录存在
        if not os.path.exists(self.OUTPUT_DIR):
            os.makedirs(self.OUTPUT_DIR)

    def record(self):
        p = pyaudio.PyAudio()

        # 打开音频流
        stream = p.open(format=self.FORMAT,
                       channels=self.CHANNELS,
                       rate=self.RATE,
                       input=True,
                       frames_per_buffer=self.CHUNK)

        print("开始录音...按 Ctrl+C 停止录音")
        frames = []

        try:
            while True:
                data = stream.read(self.CHUNK)
                frames.append(data)
        except KeyboardInterrupt:
            print("\n录音结束")

        # 停止并关闭音频流
        stream.stop_stream()
        stream.close()
        p.terminate()

        # 生成文件名
        timestamp = datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
        filename = os.path.join(self.OUTPUT_DIR, f"record_{timestamp}.wav")

        # 保存录音文件
        wf = wave.open(filename, 'wb')
        wf.setnchannels(self.CHANNELS)
        wf.setsampwidth(p.get_sample_size(self.FORMAT))
        wf.setframerate(self.RATE)
        wf.writeframes(b''.join(frames))
        wf.close()

        print(f"录音已保存至: {filename}")
        return filename

def main():
    recorder = AudioRecorder()
    recorder.record()

if __name__ == "__main__":
    main() 