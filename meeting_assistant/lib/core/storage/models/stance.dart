import 'package:isar/isar.dart';

part 'stance.g.dart';

@Collection()
class Stance {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  final String name; // 派别名称

  final String? description; // 派别描述

  @Index()
  final int meetingId; // 所属会议

  @Index()
  final DateTime? createdAt;

  Stance({
    required this.name,
    required this.meetingId,
    this.description,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // 添加工厂方法
  factory Stance.create({
    required String name,
    required int meetingId,
    String? description,
  }) {
    return Stance(
      name: name,
      meetingId: meetingId,
      description: description,
    );
  }

  // 添加 copyWith 方法
  Stance copyWith({
    String? name,
    String? description,
  }) {
    return Stance(
      name: name ?? this.name,
      meetingId: meetingId,
      description: description ?? this.description,
      createdAt: createdAt,
    );
  }
}
