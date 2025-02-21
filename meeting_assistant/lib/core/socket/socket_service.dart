import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'dart:typed_data';
import '../utils/logger.dart';
import 'socket_config.dart';
import 'meeting_service.dart';
import 'package:get/get.dart';
import '../../controllers/meeting_controller.dart';

class SocketService {
  late socket_io.Socket socket;
  Function(Map<String, dynamic>)? onTranscription;

  void initialize() {
    socket = socket_io.io(
        SocketConfig.serverUrl,
        socket_io.OptionBuilder()
            .setTransports(SocketConfig.socketOptions['transports'])
            .setPath(SocketConfig.socketOptions['path'])
            .build());

    socket.onConnect((_) async {
      Log.log.info('Connected to server');

      // 连接成功后，同步当前会议信息
      final meetingController = Get.find<MeetingController>();
      if (meetingController.currentMeeting != null) {
        try {
          await MeetingService.switchMeeting(
              meetingController.currentMeeting!.id);
          Log.log.info(
              'Synced current meeting ID: ${meetingController.currentMeeting!.id}');
        } catch (e) {
          Log.log.severe('Failed to sync meeting after reconnect: $e');
        }
      }
    });

    socket.on('transcription', (data) {
      Log.log.finest('Received transcription: $data');
      if (onTranscription != null) {
        onTranscription!(data);
      }
    });

    socket.onDisconnect((_) => Log.log.info('Disconnected from server'));
    socket.onError((err) => Log.log.severe('Socket error: $err'));
  }

  void sendAudio(Uint8List data) {
    try {
      final pcmData = Int16List.view(data.buffer);
      socket.emit('audio_stream', {
        'audio': pcmData.buffer.asUint8List(),
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0
      });
    } catch (e) {
      Log.log.severe('Failed to send audio data: $e');
    }
  }

  void stopAudioStream() {
    socket.emit('audio_stream_stop');
    Log.log.finest('Audio stream stopped');
  }

  void dispose() {
    socket.dispose();
  }
}
