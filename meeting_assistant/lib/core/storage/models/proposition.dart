import 'package:isar/isar.dart';

part 'proposition.g.dart';

@Collection()
class Proposition {
  Id id = Isar.autoIncrement;

  @Index()
  final int meetingId;

  @Index()
  final int stanceId;

  final String content; // 主张内容
  final String? note; // 备注说明

  @Index()
  final DateTime createdAt;
  final DateTime updatedAt;

  Proposition({
    required this.meetingId,
    required this.stanceId,
    required this.content,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  // 工厂方法来处理默认值
  factory Proposition.create({
    required int meetingId,
    required int stanceId,
    required String content,
    String? note,
  }) {
    final now = DateTime.now();
    return Proposition(
      meetingId: meetingId,
      stanceId: stanceId,
      content: content,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
  }

  // copyWith 方法
  Proposition copyWith({
    String? content,
    String? note,
  }) {
    final prop = Proposition(
      meetingId: meetingId,
      stanceId: stanceId,
      content: content ?? this.content,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
    prop.id = id; // 复制 ID
    return prop;
  }
}
