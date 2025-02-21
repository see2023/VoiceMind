import 'dart:async';
import 'package:get/get.dart';
import '../core/audio/audio_player_service.dart';
import '../core/storage/models/utterance.dart';
import '../core/utils/logger.dart';

class AudioPlayerController extends GetxController {
  final AudioPlayerService _playerService = AudioPlayerService();

  int? currentAudioId;
  double progress = 0.0;
  bool get isPlaying => _playerService.isPlaying;
  Timer? _progressTimer;

  // 当前播放的时间信息
  int? _startTime;
  int? _endTime;

  Future<void> playUtterance(Utterance utterance) async {
    try {
      Log.log.info('▶️ 开始处理播放请求: ${utterance.id}');

      // 如果有正在播放但不是当前点击的项，先清理前一个
      if (currentAudioId != null && currentAudioId != utterance.id) {
        final previousId = currentAudioId;
        await _playerService.stop();
        currentAudioId = utterance.id;
        _startTime = utterance.startTime;
        _endTime = utterance.endTime;
        progress = 0.0;
        update([
          'button_$previousId',
          'progress_$previousId',
          'button_${utterance.id}',
          'progress_${utterance.id}'
        ]);
        return;
      }

      if (currentAudioId == utterance.id) {
        // 同一个对话项，切换播放/暂停
        if (isPlaying) {
          await _playerService.pause();
        } else {
          await _playerService.resume();
        }
        update(['button_${utterance.id}', 'progress_${utterance.id}']);
        return;
      }

      // 新的对话项
      currentAudioId = utterance.id;
      _startTime = utterance.startTime;
      _endTime = utterance.endTime;
      progress = 0.0;
      update(['button_${utterance.id}', 'progress_${utterance.id}']);
    } catch (e) {
      Log.log.severe('❌ 播放错误: $e');
      currentAudioId = null;
      update();
    }
  }

  // 新增：处理音频数据加载和播放（调用后续启动进度计时器）
  Future<void> loadAndPlay(List<List<int>> audioData) async {
    try {
      Log.log.info('开始加载音频: id=$currentAudioId');
      await _playerService.playWavData(
        audioData,
        startTime: _startTime!,
        endTime: _endTime!,
      );
      Log.log.info(
          '音频加载完成: id=$currentAudioId, isPlaying=${_playerService.isPlaying}');
      Future.microtask(
          () => update(['button_$currentAudioId', 'progress_$currentAudioId']));
    } catch (e) {
      Log.log.severe('Failed to load and play audio: $e');
      currentAudioId = null;
      update();
    }
  }

  Future<void> seekTo(double newProgress) async {
    if (_startTime == null || _endTime == null) return;

    final totalDuration = _endTime! - _startTime!;
    final targetPosition =
        Duration(milliseconds: (totalDuration * newProgress).toInt());

    await _playerService.seekTo(targetPosition);
    progress = newProgress;
    update(['progress_$currentAudioId']);
  }

  @override
  void onClose() {
    _progressTimer?.cancel();
    _playerService.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    Log.log.info('初始化 AudioPlayerController');

    // 订阅播放状态变化流
    _playerService.playingStream.listen((playing) {
      Log.log.info(
          '播放状态流更新: playing=$playing, id=$currentAudioId, progress=$progress');
      if (!playing && progress >= 0.99) {
        progress = 0.0;
        currentAudioId = null;
      }
      update(['button_$currentAudioId', 'progress_$currentAudioId']);
    });

    // 订阅播放位置变化流，更新进度条
    _playerService.positionStream.listen((position) {
      if (_startTime == null || _endTime == null || currentAudioId == null) {
        return;
      }

      final currentPosition = position.inMilliseconds;
      final totalDuration = _endTime! - _startTime!;
      final newProgress = (currentPosition / totalDuration).clamp(0.0, 1.0);

      if (newProgress != progress) {
        progress = newProgress;
        update(['progress_$currentAudioId']);
      }

      if (newProgress >= 1.0) {
        final finishedId = currentAudioId;
        progress = 0.0;
        currentAudioId = null;
        update(['button_$finishedId', 'progress_$finishedId']);
      }
    });
  }

  // 通知特定项更新UI
  void notifyItemChanged(int itemId) {
    update(['item_$itemId']);
  }

  // 添加停止播放的方法，用于会议切换时调用
  Future<void> stopPlaying() async {
    await _playerService.stop();
    currentAudioId = null;
    progress = 0.0;
    update();
  }
}
