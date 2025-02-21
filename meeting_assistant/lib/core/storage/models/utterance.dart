import 'package:isar/isar.dart';

part 'utterance.g.dart';

@Collection()
class Utterance {
  Id id = Isar.autoIncrement;

  @Index()
  final int meetingId;

  final String text;

  @Index()
  final int? speakerId; // AI 识别的说话人ID

  @Index()
  final int? userId; // 人工确认的用户ID

  @Index()
  final int startTime;
  final int endTime;

  final bool isFinal; // 是否为API传回的最终结果
  final bool isConfirmed; // 是否已人工确认
  final String? note; // 备注或标记

  // 存储为一维数组: [start1, end1, start2, end2, ...]
  final List<int> wordTimestamps;

  Utterance({
    this.id = Isar.autoIncrement,
    required this.meetingId,
    required this.text,
    this.speakerId,
    this.userId,
    required this.startTime,
    required this.endTime,
    this.isFinal = false,
    this.isConfirmed = false,
    this.note,
    this.wordTimestamps = const [],
  });

  Utterance copyWith({
    int? id,
    int? meetingId,
    String? text,
    int? speakerId,
    int? userId,
    int? startTime,
    int? endTime,
    bool? isFinal,
    bool? isConfirmed,
    String? note,
    List<int>? wordTimestamps,
  }) {
    return Utterance(
      id: id ?? this.id,
      meetingId: meetingId ?? this.meetingId,
      text: text ?? this.text,
      speakerId: speakerId ?? this.speakerId,
      userId: userId ?? this.userId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isFinal: isFinal ?? this.isFinal,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      note: note ?? this.note,
      wordTimestamps: wordTimestamps ?? this.wordTimestamps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meetingId': meetingId,
      'text': text,
      'speaker_id': speakerId,
      'user_id': userId,
      'start_time': startTime,
      'end_time': endTime,
      'isFinal': isFinal,
      'isConfirmed': isConfirmed,
      'note': note,
      'timestamp': wordTimestamps,
    };
  }
}
