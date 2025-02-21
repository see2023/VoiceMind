import 'package:get/get.dart';
import 'dart:typed_data';
import '../core/audio/audio_service.dart';
import '../core/socket/socket_service.dart';
import '../core/utils/logger.dart';
import '../core/storage/services/isar_service.dart';
import '../core/storage/models/audio_chunk.dart';
import '../core/storage/models/utterance.dart';
import '../core/storage/models/meeting.dart';
import './meeting_controller.dart';
import '../core/utils/speaker_utils.dart';

class RecordingController extends GetxController {
  final _audioService = AudioService();
  final _socketService = SocketService();
  final _isRecording = false.obs;
  final _isInitialized = false.obs;
  final _meetingController = Get.find<MeetingController>();

  final _isLoading = false.obs;
  final _hasMore = true.obs;
  final _currentPage = 0.obs;
  static const int _pageSize = 50;

  Meeting? get currentMeeting => _meetingController.currentMeeting;

  bool get isRecording => _isRecording.value;
  bool get isInitialized => _isInitialized.value;
  List<Utterance> get conversations => _meetingController.utterances;
  bool get isLoading => _isLoading.value;
  bool get hasMore => _hasMore.value;

  // 添加一个临时记录的缓存
  final _tempUtterances = <String, Utterance>{}.obs; // key 是 speakerId

  @override
  void onInit() {
    super.onInit();
    Log.log.finest('Initializing recording controller');
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    try {
      await _meetingController.initializeComplete;

      await initialize();
      await loadInitialUtterances();

      Log.log.info('Recording controller fully initialized');
    } catch (e) {
      Log.log.severe('Failed to initialize recording controller: $e');
    }
  }

  Future<void> initialize() async {
    try {
      await _audioService.initialize();
      _socketService.initialize();
      _socketService.onTranscription = _handleTranscription;
      _isInitialized.value = true;
      Log.log.info('Recording controller initialized');
    } catch (e) {
      Log.log.severe('Failed to initialize recording controller: $e');
    }
  }

  Future<void> _handleAudioData(Uint8List audioData) async {
    try {
      final chunk = AudioChunk(
        startTime: DateTime.now().millisecondsSinceEpoch,
        duration: AudioService.chunkDurationMs,
        meetingId: _meetingController.currentMeeting!.id,
        wavData: audioData.toList(),
        sampleRate: AudioService.sampleRate,
        channels: 1,
        encoding: 'PCM16',
      );

      await IsarService.saveAudioChunk(chunk);
      _socketService.sendAudio(audioData);
    } catch (e) {
      Log.log.severe('Failed to handle audio data: $e');
    }
  }

  // 合并两段文本，处理重叠部分
  // existingText: 现有文本
  // newText: 新文本
  // existingTimestamps: 现有文本的时间戳
  // newTimestamps: 新文本的时间戳
  // baseTime: 现有文本的起始时间
  // newStartTime: 新文本的起始时间
  (String, List<int>) _mergeTextAndTimestamps(
    String existingText,
    String newText,
    List<int> existingTimestamps,
    List<int> newTimestamps,
    int baseTime,
    int newStartTime,
  ) {
    if (existingTimestamps.isEmpty) return (newText, newTimestamps);
    if (existingText.isEmpty) return (newText, newTimestamps);

    // 找到时间戳中第一个大于newStartTime的位置
    int overlapIndex = -1;
    for (int i = 0; i < existingTimestamps.length; i += 2) {
      if (existingTimestamps[i] + baseTime >= newStartTime) {
        overlapIndex = i;
        break;
      }
    }

    // 如果没有找到重叠部分，直接返回合并结果
    if (overlapIndex == -1) {
      return (
        existingText + newText,
        [
          ...existingTimestamps,
          ...newTimestamps.map((t) => t + (newStartTime - baseTime)).toList(),
        ]
      );
    }

    // 计算重叠位置对应的文本长度（每两个时间戳对应一个字）
    int overlapCharIndex = overlapIndex ~/ 2;

    // 保留existingText中不重叠的部分
    String mergedText = existingText.substring(0, overlapCharIndex) + newText;

    // 保留不重叠的时间戳，并添加新的时间戳（需要调整偏移）
    List<int> mergedTimestamps = [
      ...existingTimestamps.sublist(0, overlapIndex),
      ...newTimestamps.map((t) => t + (newStartTime - baseTime)).toList(),
    ];

    return (mergedText, mergedTimestamps);
  }

  void _handleTranscription(Map<String, dynamic> data) async {
    try {
      final meetingId = _meetingController.currentMeeting?.id;
      if (meetingId == null) return;

      // 解析基本数据
      final startTime = ((data['start_time'] as double) * 1000).toInt();
      final endTime = ((data['end_time'] as double) * 1000).toInt();
      final speakerId = SpeakerUtils.parseSpeakerId(data['speaker_id']) ?? -1;
      final isFinal = data['isFinal'] as bool;
      final text = data['text'] as String;

      // 检查文本是否只包含标点符号
      final plainText = text.replaceAll(RegExp(r'[,.!?;，。？！；\s]'), '');
      if (plainText.isEmpty) {
        Log.log.fine('Skipping utterance with only punctuation marks: $text');
        return;
      }

      final timestamps = _processTimestamps(data['timestamp']);

      Log.log.fine('''
      Handling transcription:
      - Text: $text
      - Speaker: $speakerId
      - Start: $startTime
      - End: $endTime
      - IsFinal: $isFinal
      ''');

      final utterance = Utterance(
        meetingId: meetingId,
        text: text,
        speakerId: speakerId,
        startTime: startTime,
        endTime: endTime,
        isFinal: isFinal,
        wordTimestamps: timestamps,
      );

      if (!isFinal) {
        Log.log.fine('Processing temporary utterance');
        final tempKey = speakerId.toString();
        final existingTemp = _tempUtterances[tempKey];

        if (existingTemp != null) {
          final timeGap = (startTime - existingTemp.endTime).abs();
          Log.log.fine('Existing temp found, timeGap: $timeGap ms');

          if (timeGap < 1000 || startTime < existingTemp.endTime) {
            // 合并文本和时间戳，处理重叠部分
            final (mergedText, mergedTimestamps) = _mergeTextAndTimestamps(
              existingTemp.text,
              text,
              existingTemp.wordTimestamps,
              timestamps,
              existingTemp.startTime,
              startTime,
            );

            final updatedUtterance = Utterance(
              meetingId: meetingId,
              text: mergedText,
              speakerId: speakerId,
              startTime: existingTemp.startTime,
              endTime: endTime,
              isFinal: false,
              wordTimestamps: mergedTimestamps,
            );
            _tempUtterances[tempKey] = updatedUtterance;

            final index = _meetingController.utterances
                .indexWhere((u) => !u.isFinal && u.speakerId == speakerId);
            if (index >= 0) {
              _meetingController.utterances[index] = updatedUtterance;
            }
          } else {
            _tempUtterances[tempKey] = utterance;
            _meetingController.utterances.insert(0, utterance);
          }
        } else {
          _tempUtterances[tempKey] = utterance;
          _meetingController.utterances.insert(0, utterance);
        }
      } else {
        Log.log.info('Processing final utterance');
        await IsarService.saveUtterance(utterance);

        final tempIndices = _meetingController.utterances
            .asMap()
            .entries
            .where((e) =>
                !e.value.isFinal &&
                _isTimeOverlap(
                  e.value.startTime,
                  e.value.endTime,
                  utterance.startTime,
                  utterance.endTime,
                ))
            .map((e) => e.key)
            .toList();

        Log.log.info('Removing ${tempIndices.length} temp records');
        for (final index in tempIndices.reversed) {
          _meetingController.utterances.removeAt(index);
        }

        _meetingController.utterances.insert(0, utterance);
        _tempUtterances.removeWhere((k, v) => tempIndices.contains(v));
      }
    } catch (e) {
      Log.log.severe('Failed to handle transcription: $e');
    }
  }

  Future<void> refreshUtterances() async {
    final currentMeetingId = currentMeeting?.id;
    if (currentMeetingId == null) return;

    try {
      final (utterances, _) = await IsarService.getUtterances(
        currentMeetingId,
        offset: 0,
        limit: MeetingController.pageSize,
      );

      _meetingController.utterances.clear();
      _meetingController.utterances.addAll(utterances);
      Log.log.info('Refreshed ${utterances.length} utterances');
    } catch (e) {
      Log.log.severe('Failed to refresh utterances: $e');
    }
  }

  Future<void> toggleRecording() async {
    if (!_isInitialized.value) {
      Log.log.warning('Cannot toggle recording: not initialized');
      return;
    }

    try {
      if (!_isRecording.value) {
        await _audioService.startRecording(_handleAudioData);
        _isRecording.value = true;
        Log.log.info('Recording started');
      } else {
        await _audioService.stopRecording();
        _isRecording.value = false;
        _socketService.stopAudioStream();
        Log.log.info('Recording stopped');
      }
    } catch (e) {
      Log.log.severe('Recording control failed: $e');
      Get.snackbar('错误', '录音控制失败: $e');
    }
  }

  Future<void> loadInitialUtterances() async {
    try {
      final meetingId = currentMeeting?.id;
      if (meetingId == null) return;

      _isLoading.value = true;
      final (utterances, hasMore) = await IsarService.getUtterances(
        meetingId,
        offset: 0,
        limit: _pageSize,
      );

      _meetingController.utterances.clear();
      _meetingController.utterances.addAll(utterances);
      _hasMore.value = hasMore;

      Log.log.info('Loaded initial ${utterances.length} utterances');
    } catch (e) {
      Log.log.severe('Failed to load initial utterances: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> loadMoreUtterances() async {
    try {
      final meetingId = currentMeeting?.id;
      if (meetingId == null) return;

      _isLoading.value = true;
      final (utterances, hasMore) = await IsarService.getUtterances(
        meetingId,
        offset: _meetingController.utterances.length,
        limit: _pageSize,
      );

      _meetingController.utterances.addAll(utterances);
      _hasMore.value = hasMore;

      Log.log.info('Loaded ${utterances.length} more utterances');
    } catch (e) {
      Log.log.severe('Failed to load more utterances: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  void onMeetingChanged() {
    _meetingController.utterances.clear();
    _currentPage.value = 0;
    _hasMore.value = true;

    loadInitialUtterances();

    reinitializeSocket();
  }

  Future<void> updateMeetingInfo(
    String title,
    String? objective,
    String? notes,
  ) async {
    try {
      final meeting = currentMeeting;
      if (meeting == null) return;

      final updatedMeeting = Meeting(
        id: meeting.id,
        title: title,
        objective: objective,
        notes: notes,
        createdAt: meeting.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isActive: meeting.isActive,
      );

      await IsarService.updateMeeting(updatedMeeting);
      _meetingController.refreshMeeting();

      Log.log.info('Meeting info updated: $title');
    } catch (e) {
      Log.log.severe('Failed to update meeting info: $e');
      Get.snackbar('错误', '更新会议信息失败');
    }
  }

  Future<void> reinitializeSocket() async {
    try {
      _socketService.dispose();
      _socketService.initialize();
      _socketService.onTranscription = _handleTranscription;
      Log.log.info('Socket service reinitialized');
    } catch (e) {
      Log.log.severe('Failed to reinitialize socket: $e');
      rethrow;
    }
  }

  @override
  void onClose() {
    Log.log.finest('Disposing recording controller');
    _audioService.dispose();
    _socketService.dispose();
    super.onClose();
  }

  // 获取指定索引的 Utterance
  Utterance? getUtterance(int index) {
    if (index >= 0 && index < _meetingController.utterances.length) {
      return _meetingController.utterances[index];
    }
    return null;
  }

  // 处理 Utterance 更新
  Future<void> handleUtteranceUpdate(Utterance utterance,
      {String? text, String? note}) async {
    try {
      await IsarService.updateUtterance(utterance, text: text, note: note);
      // 更新本地状态
      final index = _meetingController.utterances
          .indexWhere((conv) => conv.id == utterance.id);
      if (index != -1) {
        _meetingController.utterances[index] = utterance;
        Log.log.fine('Updated local conversation state: id=${utterance.id}');
      }
    } catch (e) {
      Log.log.severe('Failed to handle utterance update: $e');
      rethrow;
    }
  }

  List<int> _processTimestamps(dynamic timestampData) {
    if (timestampData == null) return [];

    try {
      if (timestampData is List) {
        // 处理二维数组格式的时间戳 [[start1, end1], [start2, end2], ...]
        return timestampData.expand((item) {
          if (item is List) {
            return item.map((e) => (e as num).toInt());
          }
          return <int>[];
        }).toList();
      }
    } catch (e) {
      Log.log.warning('Failed to process timestamps: $e\nData: $timestampData');
    }

    return [];
  }

  bool _isTimeOverlap(int start1, int end1, int start2, int end2) {
    return (start1 <= end2 && end1 >= start2) ||
        (start2 <= end1 && end2 >= start1);
  }
}
