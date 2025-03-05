import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:http_parser/http_parser.dart';
import '../utils/logger.dart';
import '../socket/socket_config.dart';
import '../storage/models/document.dart';

class DocumentService {
  final String _baseUrl = '${SocketConfig.apiUrl}/documents';

  // 上传文档
  Future<Map<String, dynamic>?> uploadDocument(File file,
      {String? docType = 'legal',
      String? title,
      String? description,
      DocumentVisibility visibility = DocumentVisibility.private,
      int? meetingId}) async {
    try {
      final extension = path.extension(file.path).toLowerCase();

      // 获取正确的MIME类型信息
      final mimeTypeInfo = _getMimeTypeInfo(extension);

      // 构建multipart请求
      var request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));

      // 添加文件
      request.files.add(await http.MultipartFile.fromPath('file', file.path,
          contentType:
              MediaType(mimeTypeInfo['type']!, mimeTypeInfo['subtype']!)));

      // 添加元数据
      request.fields['doc_type'] = docType ?? 'legal';
      if (title != null) request.fields['title'] = title;
      if (description != null) request.fields['description'] = description;
      request.fields['visibility'] = visibility.toString().split('.').last;
      if (meetingId != null) {
        request.fields['meeting_id'] = meetingId.toString();
      }

      // 发送请求
      final response = await request.send();
      final String decodedResponse =
          utf8.decode(await response.stream.toBytes());
      final jsonResponse = json.decode(decodedResponse);

      if (response.statusCode == 200 && jsonResponse['success'] == true) {
        Log.log
            .info('Successfully uploaded document: ${jsonResponse['doc_id']}');
        return jsonResponse;
      } else {
        Log.log.warning(
            'Failed to upload document. Status: ${response.statusCode}, Response: $decodedResponse');
        return null;
      }
    } catch (e, stackTrace) {
      Log.log.severe('Error uploading document: $e\n$stackTrace');
      return null;
    }
  }

  // 获取文档列表
  Future<List<Map<String, dynamic>>?> getDocuments(
      {int? meetingId,
      String? docType,
      String visibility = 'all',
      int page = 1,
      int limit = 20}) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'visibility': visibility
      };

      if (meetingId != null) queryParams['meeting_id'] = meetingId.toString();
      if (docType != null) queryParams['doc_type'] = docType;

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final jsonResponse = json.decode(decodedResponse);
        if (jsonResponse['success'] == true) {
          return List<Map<String, dynamic>>.from(jsonResponse['documents']);
        }
      }

      Log.log
          .warning('Failed to get documents. Status: ${response.statusCode}');
      return null;
    } catch (e, stackTrace) {
      Log.log.severe('Error getting documents: $e\n$stackTrace');
      return null;
    }
  }

  // 获取文档状态
  Future<Map<String, dynamic>?> getDocumentStatus(String docId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/$docId/status'));

      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final jsonResponse = json.decode(decodedResponse);
        if (jsonResponse['success'] == true) {
          return jsonResponse;
        }
      }

      Log.log.warning(
          'Failed to get document status. Status: ${response.statusCode}, Response: ${response.body}');
      return null;
    } catch (e, stackTrace) {
      Log.log.severe('Error getting document status: $e\n$stackTrace');
      return null;
    }
  }

  // 获取文档结构
  Future<Map<String, dynamic>?> getDocumentStructure(String docId) async {
    try {
      final uri = Uri.parse('$_baseUrl/$docId/preview');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final jsonResponse = json.decode(decodedResponse);
        if (jsonResponse['success'] == true) {
          return jsonResponse;
        }
      }

      Log.log.warning(
          'Failed to get document structure. Status: ${response.statusCode}');
      return null;
    } catch (e, stackTrace) {
      Log.log.severe('Error getting document structure: $e\n$stackTrace');
      return null;
    }
  }

  // 更新文档信息
  Future<bool> updateDocument(
      {required String docId,
      String? title,
      String? description,
      DocumentVisibility? visibility,
      int? meetingId}) async {
    try {
      final uri = Uri.parse('$_baseUrl/$docId');

      final bodyData = <String, dynamic>{};
      if (title != null) bodyData['title'] = title;
      if (description != null) bodyData['description'] = description;
      if (visibility != null) {
        bodyData['visibility'] = visibility.toString().split('.').last;
      }
      if (meetingId != null) bodyData['meeting_id'] = meetingId;

      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyData),
      );

      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final jsonResponse = json.decode(decodedResponse);
        return jsonResponse['success'] == true;
      }

      Log.log
          .warning('Failed to update document. Status: ${response.statusCode}');
      return false;
    } catch (e, stackTrace) {
      Log.log.severe('Error updating document: $e\n$stackTrace');
      return false;
    }
  }

  // 删除文档
  Future<bool> deleteDocument(String docId) async {
    try {
      final uri = Uri.parse('$_baseUrl/$docId');
      final response = await http.delete(uri);

      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final jsonResponse = json.decode(decodedResponse);
        return jsonResponse['success'] == true;
      }

      Log.log
          .warning('Failed to delete document. Status: ${response.statusCode}');
      return false;
    } catch (e, stackTrace) {
      Log.log.severe('Error deleting document: $e\n$stackTrace');
      return false;
    }
  }

  // 查询文档内容
  Future<Map<String, dynamic>?> queryDocuments({
    required String query,
    List<String>? docIds,
    DocumentVisibility? visibility,
    int? meetingId,
    int limit = 5,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/query');

      final bodyData = <String, dynamic>{
        'query': query,
        'limit': limit,
      };

      if (docIds != null && docIds.isNotEmpty) bodyData['doc_ids'] = docIds;
      if (visibility != null) {
        bodyData['visibility'] = visibility.toString().split('.').last;
      }
      if (meetingId != null) bodyData['meeting_id'] = meetingId;

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyData),
      );

      if (response.statusCode == 200) {
        final String decodedResponse = utf8.decode(response.bodyBytes);
        final jsonResponse = json.decode(decodedResponse);
        if (jsonResponse['success'] == true) {
          return jsonResponse;
        }
      }

      Log.log
          .warning('Failed to query documents. Status: ${response.statusCode}');
      return null;
    } catch (e, stackTrace) {
      Log.log.severe('Error querying documents: $e\n$stackTrace');
      return null;
    }
  }

  // 获取文件的MIME类型信息
  Map<String, String> _getMimeTypeInfo(String extension) {
    switch (extension) {
      case '.pdf':
        return {'type': 'application', 'subtype': 'pdf'};
      case '.txt':
        return {'type': 'text', 'subtype': 'plain'};
      case '.md':
        return {'type': 'text', 'subtype': 'markdown'};
      case '.docx':
        return {
          'type': 'application',
          'subtype':
              'vnd.openxmlformats-officedocument.wordprocessingml.document'
        };
      case '.doc':
        return {'type': 'application', 'subtype': 'msword'};
      case '.html':
        return {'type': 'text', 'subtype': 'html'};
      default:
        return {'type': 'application', 'subtype': 'octet-stream'};
    }
  }
}
