import 'dart:io';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import '../core/document/document_service.dart';
import '../core/storage/models/document.dart';
import '../core/utils/logger.dart';
import 'recording_controller.dart';

class DocumentController extends GetxController {
  final DocumentService _documentService = DocumentService();
  final RecordingController _recordingController =
      Get.find<RecordingController>();

  // 文档列表
  final RxList<Map<String, dynamic>> documents = <Map<String, dynamic>>[].obs;

  // 加载状态
  final RxBool isLoading = false.obs;

  // 当前选中的文档
  final Rx<Map<String, dynamic>?> selectedDocument =
      Rx<Map<String, dynamic>?>(null);

  // 文档结构预览
  final Rx<Map<String, dynamic>?> documentStructure =
      Rx<Map<String, dynamic>?>(null);

  @override
  void onInit() {
    super.onInit();
    loadDocuments();
  }

  // 加载文档列表
  Future<void> loadDocuments() async {
    isLoading.value = true;
    try {
      final currentMeeting = _recordingController.currentMeeting;
      final meetingId = currentMeeting?.id;

      final docs = await _documentService.getDocuments(
          meetingId: meetingId, visibility: 'all');

      if (docs != null) {
        documents.value = docs;
      }
    } catch (e, stackTrace) {
      Log.log.severe('Error loading documents: $e\n$stackTrace');
    } finally {
      isLoading.value = false;
    }
  }

  // 上传文档
  Future<bool> uploadDocument({
    required File file,
    String? title,
    String? description,
    String? docType,
    DocumentVisibility visibility = DocumentVisibility.private,
  }) async {
    isLoading.value = true;
    try {
      final currentMeeting = _recordingController.currentMeeting;
      final meetingId =
          visibility == DocumentVisibility.private ? currentMeeting?.id : null;

      final result = await _documentService.uploadDocument(file,
          title: title,
          description: description,
          docType: docType ?? 'legal',
          visibility: visibility,
          meetingId: meetingId);

      if (result != null) {
        await loadDocuments(); // 重新加载文档列表
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      Log.log.severe('Error uploading document: $e\n$stackTrace');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // 选择并上传文档
  Future<bool> pickAndUploadDocument({
    String? title,
    String? description,
    String? docType,
    DocumentVisibility visibility = DocumentVisibility.private,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md', 'docx', 'doc', 'html'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        final fileName = result.files.first.name;

        // 如果没有提供标题，使用文件名作为标题
        final documentTitle = title ?? fileName;

        return await uploadDocument(
          file: file,
          title: documentTitle,
          description: description,
          docType: docType,
          visibility: visibility,
        );
      } else {
        Log.log.warning('Failed to pick file or no file selected');
        return false;
      }
    } catch (e, stackTrace) {
      Log.log.severe('Error picking file: $e\n$stackTrace');
      return false;
    }
  }

  // 获取文档状态
  Future<void> checkDocumentStatus(String docId) async {
    try {
      final status = await _documentService.getDocumentStatus(docId);
      if (status != null) {
        // 更新文档列表中的状态
        final index = documents.indexWhere((doc) => doc['doc_id'] == docId);
        if (index != -1) {
          documents[index] = {...documents[index], ...status};
          documents.refresh();
        }
      }
    } catch (e, stackTrace) {
      Log.log.severe('Error checking document status: $e\n$stackTrace');
    }
  }

  // 获取文档结构预览
  Future<bool> getDocumentStructure(String docId) async {
    isLoading.value = true;
    try {
      final structure = await _documentService.getDocumentStructure(docId);
      if (structure != null) {
        documentStructure.value = structure;
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      Log.log.severe('Error getting document structure: $e\n$stackTrace');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // 更新文档信息
  Future<bool> updateDocument({
    required String docId,
    String? title,
    String? description,
    DocumentVisibility? visibility,
  }) async {
    isLoading.value = true;
    try {
      final currentMeeting = _recordingController.currentMeeting;
      final meetingId = currentMeeting?.id;

      final success = await _documentService.updateDocument(
        docId: docId,
        title: title,
        description: description,
        visibility: visibility,
        meetingId: visibility == DocumentVisibility.private ? meetingId : null,
      );

      if (success) {
        await loadDocuments(); // 刷新文档列表
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      Log.log.severe('Error updating document: $e\n$stackTrace');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // 删除文档
  Future<bool> deleteDocument(String docId) async {
    isLoading.value = true;
    try {
      final success = await _documentService.deleteDocument(docId);
      if (success) {
        await loadDocuments(); // 刷新文档列表
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      Log.log.severe('Error deleting document: $e\n$stackTrace');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // 查询文档内容
  Future<Map<String, dynamic>?> queryDocumentContent({
    required String query,
    List<String>? docIds,
    DocumentVisibility? visibility,
    int? meetingId,
    int limit = 5,
  }) async {
    isLoading.value = true;
    try {
      final currentMeeting = _recordingController.currentMeeting;
      final currentMeetingId = meetingId ?? currentMeeting?.id;

      final result = await _documentService.queryDocuments(
        query: query,
        docIds: docIds,
        visibility: visibility,
        meetingId: currentMeetingId,
        limit: limit,
      );

      return result;
    } catch (e, stackTrace) {
      Log.log.severe('Error querying document content: $e\n$stackTrace');
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  // 设置当前选中的文档
  void setSelectedDocument(Map<String, dynamic>? document) {
    selectedDocument.value = document;
  }
}
