import 'package:isar/isar.dart';

part 'meeting_participant.g.dart';

@Collection()
class MeetingParticipant {
  Id id = Isar.autoIncrement;

  @Index()
  final int meetingId; // 所属会议

  @Index()
  final int userId; // 用户ID

  @Index()
  final int? stanceId; // 在此会议中的派别

  MeetingParticipant({
    required this.meetingId,
    required this.userId,
    this.stanceId,
  });

  // 添加工厂方法
  factory MeetingParticipant.create({
    required int meetingId,
    required int userId,
    int? stanceId,
  }) {
    return MeetingParticipant(
      meetingId: meetingId,
      userId: userId,
      stanceId: stanceId,
    );
  }

  // 添加 copyWith 方法
  MeetingParticipant copyWith({
    int? stanceId,
  }) {
    return MeetingParticipant(
      meetingId: meetingId,
      userId: userId,
      stanceId: stanceId ?? this.stanceId,
    );
  }
}
