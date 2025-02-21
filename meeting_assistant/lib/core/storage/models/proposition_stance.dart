import 'package:isar/isar.dart';

part 'proposition_stance.g.dart';

@Collection()
class PropositionStance {
  Id id = Isar.autoIncrement;

  @Index()
  final int meetingId;

  @Index()
  final int propositionId; // 关联的主张

  @Index()
  final int userId; // 用户ID

  @enumerated
  final StanceType type; // 态度类型

  final String? evidence; // 支持证据（如对应的发言）
  final String? note; // 备注说明

  @Index()
  final DateTime timestamp;

  PropositionStance({
    required this.meetingId,
    required this.propositionId,
    required this.userId,
    required this.type,
    this.evidence,
    this.note,
    required this.timestamp,
  });
}

enum StanceType {
  support, // 支持
  oppose, // 反对
  neutral, // 中立
  uncertain, // 不确定
}
