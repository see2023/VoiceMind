import 'package:isar/isar.dart';

part 'speaker.g.dart';

@Collection()
class Speaker {
  Id id = Isar.autoIncrement;

  @Index()
  final int meetingId; // 所属会议

  @Index()
  final int speakerId; // 说话人ID，与 Utterance 对应

  @Index()
  final int? userId; // 关联的用户ID（可能为空，因为可能还未识别）

  final List<byte>? voiceFeature; // 声音特征数据

  Speaker({
    required this.meetingId,
    required this.speakerId,
    this.userId,
    this.voiceFeature,
  });
}
