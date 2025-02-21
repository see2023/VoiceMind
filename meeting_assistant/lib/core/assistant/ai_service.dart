import 'dart:convert';
import 'package:http/http.dart' as http;
import '../socket/socket_config.dart';
import '../utils/logger.dart';

enum MessageRole {
  system,
  user,
  assistant,
  function,
}

class Message {
  final MessageRole role;
  final String content;

  Message({
    required this.role,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
      };
}

class AIService {
  static Future<Map<String, dynamic>> analyze(
    String systemPrompt,
    String userPrompt,
  ) async {
    try {
      final messages = [
        Message(role: MessageRole.system, content: systemPrompt),
        Message(role: MessageRole.user, content: userPrompt),
      ];

      final response = await http.post(
        Uri.parse('${SocketConfig.serverUrl}/analyze_dialog'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': messages.map((m) => m.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        return jsonDecode(decodedBody);
      } else {
        throw Exception('Failed to analyze dialog: ${response.statusCode}');
      }
    } catch (e) {
      Log.log.severe('Failed to analyze with AI: $e');
      rethrow;
    }
  }
}
