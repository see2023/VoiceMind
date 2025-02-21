import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../core/utils/logger.dart';
import '../core/storage/models/utterance.dart';
import './editable_text_field.dart';
import '../core/storage/models/speaker.dart';
import '../core/storage/models/user.dart';
import '../core/storage/services/isar_service.dart';
import '../controllers/audio_player_controller.dart';

class ConversationItem extends StatefulWidget {
  final Utterance utterance;
  final VoidCallback? onPlayPressed;
  final Function(Utterance)? onUtteranceChanged;
  final Future<void> Function(int speakerId, int userId)? onSpeakerUserSelected;
  final Future<Speaker?> Function(int speakerId)? onGetSpeaker;
  final Future<List<User>> Function()? onGetUsers;
  final Future<void> Function(Utterance utterance, int speakerId, int? userId)?
      onSpeakerIdChanged;
  final Color? textColor;
  final Color? backgroundColor;

  const ConversationItem({
    super.key,
    required this.utterance,
    this.onPlayPressed,
    this.onUtteranceChanged,
    this.onSpeakerUserSelected,
    this.onGetSpeaker,
    this.onGetUsers,
    this.onSpeakerIdChanged,
    this.textColor,
    this.backgroundColor,
  });

  @override
  State<ConversationItem> createState() => _ConversationItemState();
}

class _ConversationItemState extends State<ConversationItem> {
  String? _userName;
  int? _lastSpeakerId;
  bool _isEditing = false;
  late final TextEditingController _textController;
  late final TextEditingController _notesController;
  final FocusNode _textFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();
  Speaker? _speaker;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.utterance.text);
    _notesController = TextEditingController(text: widget.utterance.note ?? '');

    // 添加键盘监听
    _textFocus.onKeyEvent = (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _notesFocus.onKeyEvent = (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _loadSpeakerInfo();
  }

  @override
  void didUpdateWidget(ConversationItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.utterance != widget.utterance ||
        oldWidget.utterance.userId != widget.utterance.userId ||
        oldWidget.utterance.speakerId != widget.utterance.speakerId ||
        oldWidget.utterance.id != widget.utterance.id) {
      Log.log.finest('Utterance updated...');
      _loadSpeakerInfo();
    }
    // 当说话人ID变化时，清除缓存的用户名
    if (widget.utterance.speakerId != _lastSpeakerId) {
      _userName = null;
      _lastSpeakerId = widget.utterance.speakerId;
    }
  }

  Future<void> _loadSpeakerInfo() async {
    if (widget.utterance.speakerId != null && widget.onGetSpeaker != null) {
      _speaker = await widget.onGetSpeaker!(widget.utterance.speakerId!);

      // 获取用户信息的逻辑
      int? userId = widget.utterance.userId ?? _speaker?.userId;

      if (userId != null && widget.onGetUsers != null) {
        final users = await widget.onGetUsers!();
        final user = users.where((u) => u.id == userId).firstOrNull;
        if (mounted) {
          setState(() {
            _userName = user?.name;
          });
        }
      }
    } else if (widget.utterance.userId != null && widget.onGetUsers != null) {
      // 直接从 userId 获取用户信息
      final users = await widget.onGetUsers!();
      final user =
          users.where((u) => u.id == widget.utterance.userId).firstOrNull;
      if (mounted) {
        setState(() {
          _userName = user?.name;
        });
      }
    } else {
      // 清除用户名，如果没有找到用户
      if (mounted) {
        setState(() {
          _userName = null;
          _speaker = null;
        });
      }
    }
  }

  Future<void> _showSpeakerSelectionDialog() async {
    if (widget.onGetUsers == null) return;

    // 获取当前会议的参与者，而不是所有用户
    final participants =
        await IsarService.getMeetingParticipants(widget.utterance.meetingId);
    if (!mounted) return;

    // 获取参与者对应的用户信息
    final users = await Future.wait(
      participants.map((p) => IsarService.getUser(p.userId)),
    );
    final validUsers = users.whereType<User>().toList(); // 过滤掉 null

    if (!mounted) return;

    // 预先获取所有参与者的 speaker 信息
    final userSpeakers = await Future.wait(
      validUsers.map((user) => _getSpeakerByUserId(user.id)),
    );
    final speakerMap = Map.fromIterables(
      validUsers.map((u) => u.id),
      userSpeakers,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('select_speaker'.tr),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当前说话人信息
              if (widget.utterance.speakerId != null) ...[
                Text('current_speaker'.tr,
                    style: const TextStyle(fontSize: 14)),
                ListTile(
                  dense: true,
                  title: Text(_formatSpeakerLabel(widget.utterance.speakerId)),
                  subtitle: _userName != null
                      ? Text('${'bound_user'.tr}: $_userName')
                      : Text('no_bound_user'.tr),
                ),
                const Divider(height: 16),
              ],
              // 选择新的说话人
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: validUsers.length,
                  itemBuilder: (_, index) {
                    final user = validUsers[index];
                    final speaker = speakerMap[user.id];

                    return ListTile(
                      dense: true,
                      title: Text(user.name),
                      subtitle: speaker != null
                          ? Text('${'speaker'.tr} ${speaker.speakerId}',
                              style: const TextStyle(fontSize: 12))
                          : null,
                      onTap: () async {
                        Navigator.of(dialogContext).pop();
                        if (widget.onSpeakerIdChanged != null) {
                          final targetSpeakerId =
                              speaker?.speakerId ?? await _getNextSpeakerId();

                          await widget.onSpeakerIdChanged!(
                            widget.utterance,
                            targetSpeakerId,
                            user.id,
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeakerLabel() {
    return FutureBuilder<String>(
      future: _getSpeakerLabel(),
      builder: (context, snapshot) {
        final label = snapshot.data ?? 'Loading...';
        return GestureDetector(
          onTap: _showSpeakerSelectionDialog,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _notesController.dispose();
    _textFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  // 取消编辑
  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      // 恢复原始内容
      _textController.text = widget.utterance.text;
      _notesController.text = widget.utterance.note ?? '';
    });
  }

  // 保存更改
  void _saveChanges() async {
    if (_textController.text == widget.utterance.text &&
        _notesController.text == (widget.utterance.note ?? '')) {
      setState(() => _isEditing = false);
      return;
    }

    Log.log.info('Saving utterance changes: '
        'text="${_textController.text}", notes="${_notesController.text}"');

    final updatedUtterance = widget.utterance.copyWith(
      text: _textController.text,
      note: _notesController.text.isEmpty ? null : _notesController.text,
      isConfirmed: true,
    );

    if (widget.onUtteranceChanged != null) {
      widget.onUtteranceChanged!(updatedUtterance);
    }

    setState(() => _isEditing = false);
  }

  void _toggleEdit() {
    if (!widget.utterance.isFinal) {
      Log.log.warning('Cannot edit non-final conversation item');
      return;
    }

    if (_isEditing) {
      Log.log.fine('Saving conversation edits');
      _saveChanges();
    } else {
      Log.log.fine('Entering conversation edit mode');
      setState(() {
        _isEditing = true;
        _textController.text = widget.utterance.text;
        _notesController.text = widget.utterance.note ?? '';
      });
      // 直接请求焦点，不需要延迟
      _textFocus.requestFocus();
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _formatSpeakerLabel(int? speakerId) {
    // 优先显示用户名（来自 utterance.userId 或 speaker.userId）
    if (_userName != null) {
      return _userName!;
    }
    // 其次显示 speaker 标签
    if (speakerId == null) return '';
    return '${'speaker_label'.tr} $speakerId';
  }

  String _truncateNote(String note) {
    const maxLength = 50;
    if (note.length <= maxLength) return note;
    return '${note.substring(0, maxLength)}...';
  }

  Future<int> _getNextSpeakerId() async {
    final meetingId = widget.utterance.meetingId;
    return await IsarService.getNextSpeakerId(meetingId);
  }

  Future<Speaker?> _getSpeakerByUserId(int userId) async {
    final meetingId = widget.utterance.meetingId;
    return await IsarService.getSpeakerByUserId(meetingId, userId);
  }

  Future<String> _getSpeakerLabel() async {
    if (widget.utterance.speakerId == null && widget.utterance.userId == null) {
      return 'Unknown';
    }

    try {
      // 使用 IsarService 的统一方法获取说话人名称
      final name = await IsarService.getUtteranceSpeakerName(widget.utterance);

      // 更新缓存
      _userName = name;
      _lastSpeakerId = widget.utterance.speakerId;

      return name;
    } catch (e) {
      Log.log.warning('Failed to get speaker label: $e');
      return widget.utterance.speakerId != null
          ? 'Speaker ${widget.utterance.speakerId}'
          : 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final utterance = widget.utterance;

    return GestureDetector(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 左侧说话人标签
                _buildSpeakerLabel(),

                // 中间进度条区域
                Expanded(
                  child: GetBuilder<AudioPlayerController>(
                    id: 'progress_${utterance.id}',
                    builder: (controller) {
                      if (controller.currentAudioId == utterance.id) {
                        return Container(
                          width: 120,
                          height: 24,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red), // 调试边界
                          ),
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              activeTrackColor: Colors.blue,
                              inactiveTrackColor: Colors.grey[300],
                            ),
                            child: Slider(
                              value: controller.progress,
                              onChanged: (value) => controller.seekTo(value),
                            ),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),

                // 右侧操作按钮区域
                Row(
                  children: [
                    if (utterance.startTime > 0)
                      Text(
                        _formatDateTime(DateTime.fromMillisecondsSinceEpoch(
                            utterance.startTime)),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    if (widget.onPlayPressed != null) ...[
                      const SizedBox(width: 8),
                      GetBuilder<AudioPlayerController>(
                        id: 'button_${utterance.id}',
                        builder: (controller) {
                          final isCurrent =
                              controller.currentAudioId == utterance.id;
                          final isPlaying = controller.isPlaying;
                          return IconButton(
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                isCurrent && isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                key: ValueKey(isCurrent && isPlaying),
                              ),
                            ),
                            onPressed: () {
                              widget.onPlayPressed?.call();
                              HapticFeedback.selectionClick();
                            },
                          );
                        },
                      ),
                    ],
                    if (utterance.isFinal) ...[
                      IconButton(
                        icon: Icon(_isEditing ? Icons.check : Icons.edit,
                            size: 18),
                        onPressed: _toggleEdit,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_isEditing) ...[
              EditableTextField(
                initialText: widget.utterance.text,
                hintText: 'conversation_text'.tr,
                textStyle: const TextStyle(fontSize: 14),
                onSave: (text) {
                  _textController.text = text;
                  _saveChanges();
                },
                onCancel: _cancelEdit,
                autofocus: true,
              ),
              EditableTextField(
                initialText: widget.utterance.note ?? '',
                hintText: 'notes_hint'.tr,
                textStyle: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: InputBorder.none,
                  prefixIcon:
                      Icon(Icons.note, size: 14, color: Colors.grey[600]),
                ),
                onSave: (text) {
                  _notesController.text = text;
                  _saveChanges();
                },
                onCancel: _cancelEdit,
              ),
            ] else ...[
              GestureDetector(
                onTapDown: (details) {
                  final controller = Get.find<AudioPlayerController>();
                  // 只有当前播放项才响应点击
                  if (controller.currentAudioId == utterance.id) {
                    final localPosition = details.localPosition;
                    final textPainter = TextPainter(
                      text: TextSpan(
                        text: utterance.text,
                        style: DefaultTextStyle.of(context).style,
                      ),
                      textDirection: TextDirection.ltr,
                    );
                    // 限制宽度，防止无限延伸
                    textPainter.layout(maxWidth: context.size?.width ?? 300);

                    // 计算点击位置对应的字符索引
                    final position =
                        textPainter.getPositionForOffset(localPosition);
                    final index = position.offset;

                    // 计算不包含标点的有效字符数量（取 substring(0,index) 后去除标点）
                    final plainText = utterance.text
                        .substring(0, index)
                        .replaceAll(RegExp(r'[,.!?;，。！？；]'), '');
                    final plainIndex = plainText.length * 2;

                    // 根据 plainIndex 从 wordTimestamps 获取时间戳
                    if (plainIndex < utterance.wordTimestamps.length) {
                      final offset = utterance.wordTimestamps[plainIndex];
                      final progress =
                          offset / (utterance.endTime - utterance.startTime);
                      controller.seekTo(progress.clamp(0.0, 1.0));
                    }
                  }
                },
                onDoubleTap: _toggleEdit,
                child: SelectableText(
                  utterance.text, // 显示原始文本
                  style: TextStyle(
                    color: utterance.isFinal
                        ? widget.textColor
                        : (widget.textColor ?? Colors.black54).withAlpha(180),
                    fontStyle: utterance.isFinal ? null : FontStyle.italic,
                  ),
                ),
              ),
              if (utterance.note?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.note, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _truncateNote(utterance.note!),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
