import 'package:isar/isar.dart';

part 'meeting.g.dart';

@Collection()
class Meeting {
  Id id = Isar.autoIncrement;

  final String title; // 会议标题
  final String? objective; // 核心目标（简单明了的一句话）
  final String? notes; // 重要说明（如时间限制、特殊要求等）

  @Index()
  final int createdAt; // 创建时间
  final int updatedAt; // 更新时间
  final bool isActive; // 是否活跃

  @Index()
  final int? lastAnalysisTime; // 最后一次分析的时间戳

  Meeting({
    this.id = Isar.autoIncrement,
    required this.title,
    this.objective,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    this.lastAnalysisTime,
  });

  // 创建新会议
  factory Meeting.create({
    required String title,
    String? objective,
    String? notes,
  }) {
    final now = DateTime.now();
    return Meeting(
      title: title,
      objective: objective,
      notes: notes,
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
      isActive: true,
      lastAnalysisTime: null,
    );
  }

  // 结束会议
  Meeting end() {
    final now = DateTime.now();
    return Meeting(
      title: title,
      objective: objective,
      notes: notes,
      createdAt: createdAt,
      updatedAt: now.millisecondsSinceEpoch,
      isActive: false,
    );
  }

  // 更新分析时间
  Meeting updateAnalysisTime() {
    final now = DateTime.now();
    return Meeting(
      id: id,
      title: title,
      objective: objective,
      notes: notes,
      createdAt: createdAt,
      updatedAt: now.millisecondsSinceEpoch,
      isActive: isActive,
      lastAnalysisTime: now.millisecondsSinceEpoch,
    );
  }
}
