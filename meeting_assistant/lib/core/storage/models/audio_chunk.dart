import 'package:isar/isar.dart';

part 'audio_chunk.g.dart';
// flutter pub run build_runner build

@Collection()
class AudioChunk {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  final int startTime; // 毫秒时间戳作为索引

  final int duration; // 固定100ms

  @Index()
  final int meetingId; // 会议ID

  final List<byte> wavData; // WAV二进制数据

  // 音频格式信息
  final int sampleRate;
  final int channels;
  final String encoding;

  AudioChunk({
    required this.startTime,
    required this.duration,
    required this.meetingId,
    required this.wavData,
    required this.sampleRate,
    required this.channels,
    required this.encoding,
  });
}
