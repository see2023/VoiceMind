import librosa
import librosa.display
import matplotlib.pyplot as plt
import numpy as np
import os
import pyworld as pw

class AudioVisualizer:
    def __init__(self, audio_file):
        self.audio_file = audio_file
        # 加载音频文件
        self.y, self.sr = librosa.load(audio_file, sr=None)  # sr=None 保持原始采样率
        
    def plot_waveform(self, ax=None):
        """绘制波形图"""
        if ax is None:
            plt.figure(figsize=(15, 3))
            ax = plt.gca()
            
        librosa.display.waveshow(self.y, sr=self.sr, ax=ax)
        ax.set_title('Waveform')
        ax.set_xlabel('Time (seconds)')
        ax.set_ylabel('Amplitude')
        
    def plot_melspectrogram(self, ax=None):
        """绘制梅尔频谱图"""
        if ax is None:
            plt.figure(figsize=(15, 5))
            ax = plt.gca()
            
        mel_spect = librosa.feature.melspectrogram(
            y=self.y, 
            sr=self.sr,
            n_mels=128,
            fmax=8000,
            n_fft=2048,
            hop_length=512,
            win_length=2048,
            window='hann',
            center=True,
            power=2.0
        )
        mel_spect_db = librosa.power_to_db(mel_spect, ref=np.max, top_db=80)
        
        img = librosa.display.specshow(
            mel_spect_db,
            y_axis='mel',
            x_axis='time',
            sr=self.sr,
            fmax=8000,
            ax=ax,
            cmap='magma',
            vmin=-80,
            vmax=0
        )
        ax.set_title('Mel Spectrogram')
        plt.colorbar(img, ax=ax, format='%+2.0f dB')
        
    def plot_spectrogram(self, ax=None):
        """绘制频谱图，聚焦在人声频率范围"""
        if ax is None:
            plt.figure(figsize=(15, 5))
            ax = plt.gca()
            
        D = librosa.stft(self.y, n_fft=2048, hop_length=512, win_length=2048)
        D_db = librosa.amplitude_to_db(np.abs(D), ref=np.max)
        
        img = librosa.display.specshow(
            D_db,
            y_axis='linear',
            x_axis='time',
            sr=self.sr,
            ax=ax,
            cmap='magma',
            vmin=-80,
            vmax=0
        )
        ax.set_ylim(0, 4000)  # 限制显示范围在人声频率范围内
        
        ax.set_title('Spectrogram (Voice Range)')
        plt.colorbar(img, ax=ax, format='%+2.0f dB')

    def plot_enhanced_spectrogram(self, ax=None):
        """绘制增强的频谱图，突出显示人声特征"""
        if ax is None:
            plt.figure(figsize=(15, 5))
            ax = plt.gca()
            
        # 1. 使用更大的窗口来提高频率分辨率
        n_fft = 4096
        hop_length = n_fft // 4
        
        # 2. 计算频谱图
        D = librosa.stft(self.y, n_fft=n_fft, hop_length=hop_length, win_length=n_fft)
        D_db = librosa.amplitude_to_db(np.abs(D), ref=np.max)
        
        # 3. 计算共振峰
        freqs = librosa.fft_frequencies(sr=self.sr, n_fft=n_fft)
        times = librosa.times_like(D)
        
        # 4. 绘制频谱图
        img = librosa.display.specshow(
            D_db,
            y_axis='linear',
            x_axis='time',
            sr=self.sr,
            ax=ax,
            cmap='magma',
            vmin=-60,  # 调整对比度
            vmax=0
        )
        
        # 5. 突出显示人声频率范围
        ax.axhspan(85, 255, color='white', alpha=0.1, label='Typical Voice F0 Range')
        ax.axhspan(500, 2000, color='yellow', alpha=0.1, label='Formant Range')
        
        ax.set_ylim(0, 4000)
        ax.set_title('Enhanced Spectrogram (Voice Features)')
        plt.colorbar(img, ax=ax, format='%+2.0f dB')
        ax.legend()

    def plot_voice_features(self, ax=None):
        """使用 WORLD vocoder 进行 F0 检测"""
        if ax is None:
            plt.figure(figsize=(15, 5))
            ax = plt.gca()
            
        # WORLD要求音频是float64类型，范围[-1, 1]
        y_normalized = librosa.util.normalize(self.y.astype(np.float64))
        
        # 使用WORLD进行F0检测，调整参数
        _f0, t = pw.dio(
            y_normalized, 
            self.sr,
            f0_floor=50,        # 最低频率
            f0_ceil=600,        # 调整最高频率到600Hz
            frame_period=5.0    # 帧移（毫秒）
        )
        
        # 使用 stonemask 进行精确修正
        f0 = pw.stonemask(y_normalized, _f0, t, self.sr)
        
        # 生成时间轴
        times = np.arange(len(f0)) * pw.default_frame_period / 1000.0
        
        # 绘制F0曲线
        ax.plot(times, f0, label='F0', alpha=0.8, color='blue', linewidth=2)
        
        # 添加能量曲线
        ax2 = ax.twinx()
        S = np.abs(librosa.stft(y_normalized))
        energy = np.mean(S, axis=0)
        energy = energy / np.max(energy)
        energy_times = librosa.times_like(S)
        ax2.plot(energy_times, energy, color='red', alpha=0.2, label='Energy')
        ax2.set_ylabel('Energy')
        ax2.set_ylim(0, 1)
        
        # 添加典型语音频率范围的背景
        ax.axhspan(85, 155, color='blue', alpha=0.1, label='Male F0')
        ax.axhspan(165, 255, color='red', alpha=0.1, label='Female F0')
        ax.axhspan(250, 400, color='pink', alpha=0.1, label='High Female F0')
        ax.axhspan(400, 600, color='purple', alpha=0.05, label='Very High F0')
        
        # 设置图例
        lines1, labels1 = ax.get_legend_handles_labels()
        lines2, labels2 = ax2.get_legend_handles_labels()
        ax.legend(lines1 + lines2, labels1 + labels2, loc='upper right')
        
        ax.set_ylabel('Frequency (Hz)')
        ax.set_xlabel('Time (s)')
        ax.set_title('Fundamental Frequency (F0) and Signal Energy')
        ax.grid(True)
        ax.set_ylim(0, 600)  # 调整显示范围与 f0_ceil 一致
        ax.set_xlim(0, max(times))

    def visualize_all(self, save_path=None):
        """生成所有可视化图表"""
        fig, axes = plt.subplots(5, 1, figsize=(15, 20))  # 增加一个子图
        plt.subplots_adjust(hspace=0.4)
        
        fig.suptitle('Audio Analysis', fontsize=16, y=0.95)
        
        self.plot_waveform(axes[0])
        self.plot_melspectrogram(axes[1])
        self.plot_spectrogram(axes[2])
        self.plot_enhanced_spectrogram(axes[3])  # 添加增强的频谱图
        self.plot_voice_features(axes[4])
        
        if save_path:
            plt.savefig(save_path, bbox_inches='tight', dpi=300)
            print(f"Figure saved to: {save_path}")
        else:
            plt.show()

def visualize_audio(audio_file):
    """便捷函数用于快速可视化音频文件"""
    visualizer = AudioVisualizer(audio_file)
    
    # 生成保存路径（与音频文件同目录）
    base_name = os.path.splitext(audio_file)[0]
    save_path = f"{base_name}_analysis.png"
    
    visualizer.visualize_all(save_path)

def main():
    """分析最新的几个音频文件"""
    # 获取数据目录
    data_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
    wav_files = [f for f in os.listdir(data_dir) if f.endswith('.wav')]
    if not wav_files:
        print("未找到WAV文件")
        return
        
    # 按修改时间排序
    wav_files.sort(key=lambda x: os.path.getmtime(os.path.join(data_dir, x)), reverse=True)
    
    # 取最新的5个文件
    MAX_FILES = 5
    recent_files = wav_files[:MAX_FILES]
    
    print(f"正在分析最新的 {len(recent_files)} 个音频文件...")
    
    # 分析每个文件
    for wav_file in recent_files:
        audio_path = os.path.join(data_dir, wav_file)
        print(f"\n分析文件: {wav_file}")
        try:
            visualize_audio(audio_path)
        except Exception as e:
            print(f"处理文件 {wav_file} 时出错: {str(e)}")
            continue

if __name__ == "__main__":
    main() 