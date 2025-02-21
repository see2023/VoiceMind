import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/conversation_item.dart';
import '../core/audio/audio_player_service.dart';
import '../core/storage/services/isar_service.dart';
import '../core/utils/logger.dart';
import '../core/storage/models/utterance.dart';
import '../core/storage/models/speaker.dart';
import '../core/storage/models/user.dart';
import '../core/storage/models/meeting.dart'; // 添加 Meeting 类的导入
import '../controllers/meeting_controller.dart';
import 'dart:async';
import '../core/utils/stance_colors.dart'; // 导入新的颜色工具类
import '../controllers/audio_player_controller.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> {
  final _audioPlayer = AudioPlayerService();
  final _meetingController = Get.find<MeetingController>();
  final ScrollController _scrollController = ScrollController();

  // 添加一个变量记录当前列表长度，用于判断是否有新消息
  int _previousLength = 0;

  // 添加用于防抖的 Timer
  Timer? _loadMoreTimer;
  final _isLoadingMore = false.obs;

  // 添加缓存机制
  final Map<String, Color> _colorCache = {};

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    _loadMoreTimer?.cancel(); // 清理 Timer
    super.dispose();
  }

  Future<void> _playAudio(Utterance utterance) async {
    try {
      final controller = Get.find<AudioPlayerController>();

      // 如果是同一个音频，只需要切换播放状态
      if (controller.currentAudioId == utterance.id) {
        await controller.playUtterance(utterance);
        return;
      }

      final meetingId = _meetingController.currentMeeting?.id;
      if (meetingId == null) return;

      // 新的音频：先通知控制器准备播放
      await controller.playUtterance(utterance);

      final chunks = await IsarService.getAudioChunks(
        meetingId,
        utterance.startTime,
        utterance.endTime,
      );

      if (chunks.isEmpty) return;

      // 加载并播放音频
      await controller.loadAndPlay(chunks.map((c) => c.wavData).toList());
    } catch (e) {
      Log.log.severe('Play failed: $e');
    }
  }

  // 处理说话人相关功能
  Future<void> _handleSpeakerUserSelected(int speakerId, int userId) async {
    try {
      final meetingId = _meetingController.currentMeeting?.id;
      if (meetingId == null) return;

      final tempUtterance = Utterance(
        meetingId: meetingId,
        text: '',
        startTime: 0,
        endTime: 0,
        speakerId: speakerId,
      );

      await IsarService.updateUtteranceUser(tempUtterance, userId);
      await _meetingController
          .refreshUtterances(); // 使用 MeetingController 的刷新方法
    } catch (e) {
      Log.log.severe('Failed to update speaker user: $e');
      Get.snackbar('error'.tr, 'update_failed'.tr);
    }
  }

  Future<void> _handleSpeakerIdChanged(
    Utterance utterance,
    int speakerId,
    int? userId,
  ) async {
    try {
      // 更新说话人ID和用户ID
      await IsarService.updateUtteranceUser(utterance, userId);

      if (userId != null) {
        final actualSpeakerId = utterance.speakerId;
        if (actualSpeakerId != null) {
          Log.log.info(
              'Creating speaker mapping with actual speakerId: $actualSpeakerId');
          // 创建说话人映射
          await IsarService.createSpeakerMapping(
            utterance.meetingId,
            actualSpeakerId,
            userId,
          );
        }
      }

      // 使用 MeetingController 刷新对话列表
      await _meetingController.refreshUtterances();

      Log.log.info(
          'Utterance user updated: id=${utterance.id}, speakerId=${utterance.speakerId}, userId=$userId');
    } catch (e) {
      Log.log.severe('Failed to update utterance user: $e');
      Get.snackbar('error'.tr, 'update_failed'.tr);
    }
  }

  Future<Speaker?> _getSpeaker(int speakerId) async {
    final meetingId = _meetingController.currentMeeting?.id;
    if (meetingId == null) return null;
    return await IsarService.getSpeaker(meetingId, speakerId);
  }

  Future<List<User>> _getUsers() async {
    return await IsarService.getAllUsers();
  }

  // 修改防抖的加载方法
  void _debouncedLoadMore(double currentPosition) {
    if (_isLoadingMore.value) return; // 使用 .value

    _loadMoreTimer?.cancel();
    _loadMoreTimer = Timer(const Duration(milliseconds: 100), () async {
      // 减少到100ms
      if (!_meetingController.isLoading && _meetingController.hasMore) {
        _isLoadingMore.value = true; // 立即显示加载指示器
        try {
          await _meetingController.loadMoreUtterances();
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(currentPosition);
          }
        } finally {
          _isLoadingMore.value = false;
        }
      }
    });
  }

  // 修改颜色计算方法，添加缓存
  Future<(Color, Color)> _getItemColors(Utterance utterance) async {
    // 生成缓存key
    final cacheKey =
        '${utterance.id}_${utterance.userId}_${utterance.speakerId}';

    // 如果缓存中有，直接返回
    if (_colorCache.containsKey(cacheKey)) {
      final bgColor = _colorCache[cacheKey]!;
      return (bgColor, StanceColors.getTextColor(bgColor));
    }

    // 先尝试从 utterance.userId 获取
    final participant = _meetingController.participants
        .firstWhereOrNull((p) => p.userId == utterance.userId);
    var stanceId = participant?.stanceId;
    var userId = utterance.userId;

    // 如果没有 userId，但有 speakerId，通过 _getSpeaker 获取 userId
    if (userId == null && utterance.speakerId != null) {
      final speaker = await _getSpeaker(utterance.speakerId!);
      if (speaker != null) {
        final speakerParticipant = _meetingController.participants
            .firstWhereOrNull((p) => p.userId == speaker.userId);
        stanceId = speakerParticipant?.stanceId;
        userId = speaker.userId;
      }
    }

    // 计算颜色
    final backgroundColor = (stanceId != null && userId != null)
        ? StanceColors.getMemberBackgroundColor(stanceId, userId)
        : Colors.grey[100]!;

    // 存入缓存
    _colorCache[cacheKey] = backgroundColor;

    return (backgroundColor, StanceColors.getTextColor(backgroundColor));
  }

  Future<Widget> _buildConversationItem(Utterance utterance) async {
    final (backgroundColor, textColor) = await _getItemColors(utterance);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConversationItem(
        utterance: utterance,
        textColor: textColor,
        backgroundColor: Colors.transparent,
        onUtteranceChanged: _meetingController.updateUtterance,
        onPlayPressed: () => _playAudio(utterance),
        onSpeakerUserSelected: _handleSpeakerUserSelected,
        onGetSpeaker: _getSpeaker,
        onGetUsers: _getUsers,
        onSpeakerIdChanged: _handleSpeakerIdChanged,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 只监听会议切换
    ever<Meeting?>(_meetingController.currentMeeting.obs, (_) {
      _clearColorCache();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetX<MeetingController>(
      builder: (controller) {
        // 监听 utterances 变化并更新颜色缓存
        final newUtterances = controller.utterances
            .where((u) => !u.isFinal)
            .map((u) => '${u.id}_${u.userId}_${u.speakerId}')
            .toList();

        // 清除新句子的颜色缓存
        _colorCache.removeWhere((key, _) => newUtterances.contains(key));

        final currentLength = controller.utterances.length;

        // 只在有新消息（不是加载更多）时自动滚动到底部
        if (currentLength > _previousLength && !controller.isLoading) {
          // 只有在接近底部时才自动滚动
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              // 检查当前是否在底部附近
              final position = _scrollController.position;
              if (position.pixels < 100) {
                // 如果在底部附近，才自动滚动
                _scrollController.jumpTo(0);
              }
            }
          });
        }
        _previousLength = currentLength;

        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo is ScrollUpdateNotification) {
              final distanceToTop = scrollInfo.metrics.maxScrollExtent -
                  scrollInfo.metrics.pixels;

              if (distanceToTop < 500 &&
                  !_isLoadingMore.value && // 使用 RxBool 检查
                  controller.hasMore) {
                _debouncedLoadMore(scrollInfo.metrics.pixels);
              }
            }
            return true;
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8.0),
            reverse: true,
            itemCount: controller.utterances.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (controller.hasMore && _isLoadingMore.value) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                return const SizedBox();
              }

              final utterance = controller.utterances[index - 1];
              return FutureBuilder<Widget>(
                future: _buildConversationItem(utterance),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return snapshot.data!;
                  }
                  // 在加载时显示一个占位符
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const SizedBox(height: 50),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // 在需要时清除缓存
  void _clearColorCache() {
    _colorCache.clear();
  }
}
