import 'logger.dart';

class SpeakerUtils {
  static int? parseSpeakerId(dynamic speakerId) {
    if (speakerId == null) return null;
    if (speakerId is int) return speakerId;
    if (speakerId is String) {
      if (speakerId.isEmpty) return 0;
      return int.tryParse(speakerId.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    Log.log
        .warning('SpeakerUtils: unknown value type: ${speakerId.runtimeType}');
    return null;
  }
}
