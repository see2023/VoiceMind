import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import '../utils/logger.dart';

class AudioService {
  static const int chunkDurationMs = 100; // 音频片段时长
  static const int sampleRate = 16000; // 采样率
  static const int samplesPerChunk = sampleRate * chunkDurationMs ~/ 1000;

  final _recorder = AudioRecorder();
  bool _isRecording = false;
  StreamSubscription? _audioStreamSubscription;

  Future<void> initialize() async {
    try {
      if (!await _recorder.hasPermission()) {
        Log.log.warning('Microphone permission denied');
        throw Exception('Microphone permission denied');
      }
      Log.log.info('Audio service initialized successfully');
    } catch (e) {
      Log.log.severe('Failed to initialize audio service: $e');
      rethrow;
    }
  }

  Future<void> startRecording(void Function(Uint8List) onData) async {
    try {
      if (_isRecording) {
        Log.log.warning('Recording already in progress');
        return;
      }

      // 配置录音参数
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: sampleRate,
      );

      // 开始录音流
      final stream = await _recorder.startStream(config);

      // 处理音频数据
      _audioStreamSubscription = stream.listen(
        (data) {
          try {
            onData(Uint8List.fromList(data));
          } catch (e) {
            Log.log.severe('Error processing audio data: $e');
          }
        },
        onError: (error) {
          Log.log.severe('Audio stream error: $error');
        },
      );

      _isRecording = true;
      Log.log.info('Started recording');
    } catch (e) {
      Log.log.severe('Failed to start recording: $e');
      await stopRecording();
      rethrow;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) {
      Log.log.finest('No recording in progress');
      return;
    }

    try {
      await _audioStreamSubscription?.cancel();
      await _recorder.stop();
      _isRecording = false;
      Log.log.info('Stopped recording');
    } catch (e) {
      Log.log.severe('Error stopping recording: $e');
      rethrow;
    }
  }

  bool get isRecording => _isRecording;

  void dispose() {
    try {
      stopRecording();
      _recorder.dispose();
      Log.log.info('Audio service disposed');
    } catch (e) {
      Log.log.severe('Error disposing audio service: $e');
    }
  }
}
