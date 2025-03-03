import 'package:isar/isar.dart';

part 'document.g.dart';

@collection
class Document {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  String? docId; // 服务器端文档ID

  String? title;
  String? originalFilename;
  String? contentType;
  String? fileExtension;
  String? docType; // legal, article, etc.
  String? description;

  @enumerated
  DocumentVisibility visibility = DocumentVisibility.private;

  int? meetingId; // 关联的会议ID，私有文档需要

  @enumerated
  DocumentStatus status = DocumentStatus.pending;

  double progress = 0.0; // 处理进度 0.0-1.0

  int? chunksCount; // 文档切分后的块数量
  String? structureSummary; // 文档结构摘要

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}

enum DocumentVisibility { public, private }

enum DocumentStatus { pending, processing, completed, failed }
