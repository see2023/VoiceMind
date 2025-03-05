import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/translation_helpers.dart';
import '../core/socket/socket_config.dart';

class DocumentItem extends StatelessWidget {
  final Map<String, dynamic> document;
  final VoidCallback onTap;
  final VoidCallback onPreview;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const DocumentItem({
    Key? key,
    required this.document,
    required this.onTap,
    required this.onPreview,
    required this.onDelete,
    required this.onEdit,
  }) : super(key: key);

  // 在浏览器中打开文件
  void _openFileInBrowser() async {
    final docId = document['doc_id'] as String;
    final fileUrl = SocketConfig.getDocumentViewUrl(docId);

    try {
      // 使用浏览器打开文件
      await launchUrl(Uri.parse(fileUrl),
          mode: LaunchMode.externalApplication // 在外部浏览器中打开
          );
    } catch (e) {
      Get.snackbar(
        'error'.tr,
        'cannot_open_file'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = document['title'] ?? 'untitled'.tr;
    final status = document['status'] ?? 'unknown';
    final progress = document['progress'] as num? ?? 0;
    final docType = document['doc_type'] ?? 'unknown';
    final visibility = document['visibility'] ?? 'private';

    // 状态颜色
    Color statusColor;
    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        break;
      case 'processing':
        statusColor = Colors.blue;
        break;
      case 'failed':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    // 文档类型图标
    IconData typeIcon;
    switch (docType) {
      case 'legal':
        typeIcon = Icons.gavel;
        break;
      case 'article':
        typeIcon = Icons.article;
        break;
      case 'educational':
        typeIcon = Icons.school;
        break;
      default:
        typeIcon = Icons.description;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onPreview,
        child: Column(
          children: [
            ListTile(
              leading: Icon(typeIcon),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          TranslationHelpers.translateStatus(status),
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Text(
                          TranslationHelpers.translateVisibility(visibility),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'summary':
                      onPreview();
                      break;
                    case 'view':
                      _openFileInBrowser();
                      break;
                    case 'edit':
                      onEdit();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'summary',
                    child: Row(
                      children: [
                        const Icon(Icons.summarize, size: 20),
                        const SizedBox(width: 8),
                        Text('view_summary'.tr),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'view',
                    child: Row(
                      children: [
                        const Icon(Icons.visibility, size: 20),
                        const SizedBox(width: 8),
                        Text('view_document'.tr),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 20),
                        const SizedBox(width: 8),
                        Text('edit'.tr),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 20, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          'delete'.tr,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (status == 'processing')
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress / 100 : null,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
