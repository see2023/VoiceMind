import 'package:http/http.dart' as http;
import '../utils/logger.dart';
import 'socket_config.dart';

class MeetingService {
  static Future<bool> switchMeeting(int meetingId) async {
    try {
      final response = await http.post(
        Uri.parse('${SocketConfig.serverUrl}/switch_meeting'),
        body: {'meeting_id': meetingId.toString()},
      );

      if (response.statusCode == 200) {
        Log.log.info('Successfully switched meeting to ID: $meetingId');
        return true;
      } else {
        Log.log.warning(
            'Failed to switch meeting. Status: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      Log.log.severe('Error switching meeting: $e\n$stackTrace');
      return false;
    }
  }
}
