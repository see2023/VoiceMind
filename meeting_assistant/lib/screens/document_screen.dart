import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/document_controller.dart';
import '../core/storage/models/document.dart';
import '../widgets/document_item.dart';
import '../widgets/document_upload_dialog.dart';
import '../widgets/document_preview_dialog.dart';
import '../core/utils/translation_helpers.dart';

class DocumentScreen extends StatelessWidget {
  final DocumentController controller = Get.put(DocumentController());

  DocumentScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('documents'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.loadDocuments,
            tooltip: 'refresh'.tr,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadDialog(context),
        tooltip: 'upload_document'.tr,
        child: const Icon(Icons.add),
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.documents.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.documents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text('no_documents'.tr, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _showUploadDialog(context),
                  icon: const Icon(Icons.upload_file),
                  label: Text('upload_document'.tr),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: controller.loadDocuments,
          child: ListView.builder(
            itemCount: controller.documents.length,
            itemBuilder: (context, index) {
              final document = controller.documents[index];
              return DocumentItem(
                document: document,
                onTap: () => _showDocumentDetails(context, document),
                onPreview: () => _showDocumentPreview(context, document),
                onDelete: () => _confirmDelete(context, document),
                onEdit: () => _showEditDialog(context, document),
              );
            },
          ),
        );
      }),
    );
  }

  // 显示上传对话框
  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => DocumentUploadDialog(
        onUpload: (file, title, description, docType, visibility) {
          return controller.uploadDocument(
            file: file,
            title: title,
            description: description,
            docType: docType,
            visibility: visibility,
          );
        },
      ),
    );
  }

  // 显示文档详情
  void _showDocumentDetails(
      BuildContext context, Map<String, dynamic> document) {
    // 临时显示详情对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(document['title'] ?? 'untitled'.tr),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (document['description'] != null) ...[
                Text('description'.tr,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(document['description']),
                const SizedBox(height: 8),
              ],
              Text('document_type'.tr,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(TranslationHelpers.translateDocType(
                  document['doc_type'] ?? 'unknown')),
              const SizedBox(height: 8),
              Text('visibility'.tr,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(TranslationHelpers.translateVisibility(
                  document['visibility'] ?? 'unknown')),
              const SizedBox(height: 8),
              Text('status'.tr,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(TranslationHelpers.translateStatus(
                  document['status'] ?? 'unknown')),
              if (document['progress'] != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: document['progress'] / 100),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }

  // 显示文档预览
  void _showDocumentPreview(
      BuildContext context, Map<String, dynamic> document) async {
    final docId = document['doc_id'];
    if (docId == null) return;

    final success = await controller.getDocumentStructure(docId);
    if (success) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => DocumentPreviewDialog(
            document: document,
            structure: controller.documentStructure.value!,
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('failed_to_load_preview'.tr)),
        );
      }
    }
  }

  // 确认删除
  void _confirmDelete(BuildContext context, Map<String, dynamic> document) {
    final docId = document['doc_id'];
    if (docId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('confirm_delete'.tr),
        content: Text('delete_document_confirm'
            .trParams({'title': document['title'] ?? 'untitled'.tr})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await controller.deleteDocument(docId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'document_deleted'.tr
                        : 'failed_to_delete'.tr),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
  }

  // 显示编辑对话框
  void _showEditDialog(BuildContext context, Map<String, dynamic> document) {
    final docId = document['doc_id'];
    if (docId == null) return;

    final titleController = TextEditingController(text: document['title']);
    final descriptionController =
        TextEditingController(text: document['description']);
    DocumentVisibility visibility = document['visibility'] == 'public'
        ? DocumentVisibility.public
        : DocumentVisibility.private;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('edit_document'.tr),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'title'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'description'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DocumentVisibility>(
                  value: visibility,
                  decoration: InputDecoration(
                    labelText: 'visibility'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: DocumentVisibility.public,
                      child: Text('public'.tr),
                    ),
                    DropdownMenuItem(
                      value: DocumentVisibility.private,
                      child: Text('private'.tr),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      visibility = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final success = await controller.updateDocument(
                  docId: docId,
                  title: titleController.text,
                  description: descriptionController.text,
                  visibility: visibility,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'document_updated'.tr
                          : 'failed_to_update'.tr),
                    ),
                  );
                }
              },
              child: Text('save'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
