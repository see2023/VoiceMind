import 'dart:io';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  static const String _cacheDir = 'audio_cache';

  bool get isPlaying => _player.playing;
  Duration? get position => _player.position;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;

  Future<String> _getCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$_cacheDir');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  String _getAudioFileName(int startTime, int endTime) {
    return 'audio_${startTime}_$endTime.wav';
  }

  Future<File> _ensureAudioFile(
    List<List<int>> chunks,
    int startTime,
    int endTime,
  ) async {
    final cacheDir = await _getCacheDir();
    final fileName = _getAudioFileName(startTime, endTime);
    final file = File('$cacheDir/$fileName');

    // 如果文件已存在，直接返回
    if (await file.exists()) {
      Log.log.info('Using cached audio file: $fileName');
      return file;
    }

    // 创建新文件
    Log.log.info('Creating new audio file: $fileName');
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final wavHeader = _createWavHeader(totalLength);

    final wavFile = Uint8List(wavHeader.length + totalLength);
    wavFile.setAll(0, wavHeader);

    var offset = wavHeader.length;
    for (var chunk in chunks) {
      wavFile.setAll(offset, chunk);
      offset += chunk.length;
    }

    await file.writeAsBytes(wavFile);
    return file;
  }

  Future<void> playWavData(
    List<List<int>> chunks, {
    required int startTime,
    required int endTime,
  }) async {
    try {
      final audioFile = await _ensureAudioFile(chunks, startTime, endTime);
      await _player.setFilePath(audioFile.path);
      await _player.play();
      Log.log.info('音频开始播放: ${audioFile.path}');
    } catch (e) {
      Log.log.severe('Failed to play audio: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    Log.log.info('暂停播放');
    await _player.pause();
    // 确保状态变化后发送通知
    _player.playingStream.first;
  }

  Future<void> resume() async {
    Log.log.info('继续播放');
    await _player.play();
    // 确保状态变化后发送通知
    _player.playingStream.first;
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  Uint8List _createWavHeader(
    int dataSize, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final header = ByteData(44); // WAV header is 44 bytes

    // RIFF chunk descriptor
    header.setUint32(0, 0x52494646, Endian.big); // 'RIFF' in ASCII
    header.setUint32(4, 36 + dataSize, Endian.little); // File size - 8
    header.setUint32(8, 0x57415645, Endian.big); // 'WAVE' in ASCII

    // fmt sub-chunk
    header.setUint32(12, 0x666D7420, Endian.big); // 'fmt ' in ASCII
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, channels, Endian.little); // NumChannels
    header.setUint32(24, sampleRate, Endian.little); // SampleRate
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8,
        Endian.little); // ByteRate
    header.setUint16(
        32, channels * bitsPerSample ~/ 8, Endian.little); // BlockAlign
    header.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample

    // data sub-chunk
    header.setUint32(36, 0x64617461, Endian.big); // 'data' in ASCII
    header.setUint32(40, dataSize, Endian.little); // Subchunk2Size

    return header.buffer.asUint8List();
  }

  void dispose() {
    _player.dispose();
  }
}
