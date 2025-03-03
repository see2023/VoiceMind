import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import '../core/storage/models/document.dart';
import '../core/utils/logger.dart';

typedef UploadCallback = Future<bool> Function(
  File file,
  String? title,
  String? description,
  String? docType,
  DocumentVisibility visibility,
);

class DocumentUploadDialog extends StatefulWidget {
  final UploadCallback onUpload;

  const DocumentUploadDialog({
    Key? key,
    required this.onUpload,
  }) : super(key: key);

  @override
  State<DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<DocumentUploadDialog> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  String? selectedDocType = 'legal';
  DocumentVisibility visibility = DocumentVisibility.private;

  File? selectedFile;
  String? fileName;
  bool isUploading = false;
  String? errorMessage;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      Log.log.info("开始选择文件...");

      // Add more detailed logging
      Log.log.info(
          "FilePicker配置: type=custom, extensions=[pdf, txt, md, docx, doc, html]");

      var result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'docx', 'doc', 'html'],
        dialogTitle: '选择文档文件',
        allowCompression: false,
        withData: false,
        withReadStream: true,
        lockParentWindow: true,
      );
      Log.log.info("文件选择结果: $result");
      // Add more details about the platform
      Log.log.info(
          "运行平台: ${Platform.operatingSystem}, ${Platform.operatingSystemVersion}");

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          selectedFile = File(result.files.first.path!);
          fileName = result.files.first.name;

          // 如果标题为空，使用文件名作为标题
          if (titleController.text.isEmpty) {
            titleController.text = fileName!;
          }
        });
      } else {
        Log.log.warning("用户未选择文件或FilePicker对话框未显示");
      }
    } catch (e, stackTrace) {
      Log.log.severe("文件选择错误: $e");
      Log.log.severe("堆栈跟踪: $stackTrace");
      setState(() {
        errorMessage = 'failed_to_pick_file'.tr;
      });
    }
  }

  Future<void> _uploadFile() async {
    if (selectedFile == null) {
      setState(() {
        errorMessage = 'please_select_file'.tr;
      });
      return;
    }

    setState(() {
      isUploading = true;
      errorMessage = null;
    });

    try {
      final success = await widget.onUpload(
        selectedFile!,
        titleController.text.isNotEmpty ? titleController.text : null,
        descriptionController.text.isNotEmpty
            ? descriptionController.text
            : null,
        selectedDocType,
        visibility,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          errorMessage = 'failed_to_upload'.tr;
          isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'error_uploading'.tr;
        isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('upload_document'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件选择
            ElevatedButton.icon(
              onPressed: isUploading ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text('select_file'.tr),
            ),
            if (fileName != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.description, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName!,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // 标题
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'title'.tr,
                border: const OutlineInputBorder(),
              ),
              enabled: !isUploading,
            ),
            const SizedBox(height: 16),

            // 描述
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: 'description'.tr,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: !isUploading,
            ),
            const SizedBox(height: 16),

            // 文档类型
            DropdownButtonFormField<String>(
              value: selectedDocType,
              decoration: InputDecoration(
                labelText: 'document_type'.tr,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'legal', child: Text('legal'.tr)),
                DropdownMenuItem(value: 'article', child: Text('article'.tr)),
                DropdownMenuItem(
                    value: 'educational', child: Text('educational'.tr)),
                DropdownMenuItem(value: 'other', child: Text('other'.tr)),
              ],
              onChanged: isUploading
                  ? null
                  : (value) {
                      setState(() {
                        selectedDocType = value;
                      });
                    },
            ),
            const SizedBox(height: 16),

            // 可见性
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
              onChanged: isUploading
                  ? null
                  : (value) {
                      setState(() {
                        visibility = value!;
                      });
                    },
            ),

            // 错误信息
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],

            // 上传进度
            if (isUploading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Center(child: Text('uploading'.tr)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isUploading ? null : () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          onPressed: isUploading ? null : _uploadFile,
          child: Text('upload'.tr),
        ),
      ],
    );
  }
}
