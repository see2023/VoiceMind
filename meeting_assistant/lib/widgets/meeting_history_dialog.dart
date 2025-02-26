import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/meeting_controller.dart';
import 'meeting_info_dialog.dart';
import 'package:flutter/services.dart';

class MeetingHistoryDialog extends StatefulWidget {
  const MeetingHistoryDialog({super.key});

  @override
  State<MeetingHistoryDialog> createState() => _MeetingHistoryDialogState();
}

class _MeetingHistoryDialogState extends State<MeetingHistoryDialog> {
  // Method to handle audio export
  void _handleAudioExport(int meetingId) {
    // Using unawaited Future to avoid BuildContext warnings
    _exportAudio(meetingId);
  }

  // Async implementation without BuildContext
  Future<void> _exportAudio(int meetingId) async {
    final result =
        await Get.find<MeetingController>().exportMeetingAudio(meetingId);
    if (result != null && mounted) {
      _showExportSnackBar(result);
    }
  }

  // Helper method to show export snackbar
  void _showExportSnackBar(String filePath, {bool isText = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${(isText ? 'text_exported' : 'audio_exported').tr}: $filePath'),
        action: SnackBarAction(
          label: 'open_folder'.tr,
          onPressed: () =>
              Get.find<MeetingController>().openExportFolder(filePath),
        ),
      ),
    );
  }

  // Method to handle text export
  void _handleTextExport(int meetingId) {
    // Using unawaited Future to avoid BuildContext warnings
    _exportText(meetingId);
  }

  // Async implementation without BuildContext
  Future<void> _exportText(int meetingId) async {
    final result =
        await Get.find<MeetingController>().exportMeetingText(meetingId);
    if (result != null && mounted) {
      _showTextPreviewDialog(result.text, result.title);
    }
  }

  // Show text preview dialog
  void _showTextPreviewDialog(String text, String title) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('text_export_preview'.tr),
        content: SizedBox(
          width: double.maxFinite,
          height: 400, // Increased height
          child: SingleChildScrollView(
            child: SelectableText(text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text('copied_to_clipboard'.tr)),
              );
            },
            child: Text('copy'.tr),
          ),
          TextButton(
            onPressed: () {
              // Non-async callback that triggers async function
              _handleSaveText(dialogContext, text, title);
            },
            child: Text('save'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }

  // Handle save text button press
  void _handleSaveText(BuildContext dialogContext, String text, String title) {
    // Using unawaited Future to avoid BuildContext warnings
    _saveTextToFile(dialogContext, text, title);
  }

  // Async implementation of text saving
  Future<void> _saveTextToFile(
      BuildContext dialogContext, String text, String title) async {
    final filePath =
        await Get.find<MeetingController>().saveTextToFile(text, title);
    if (filePath != null) {
      // ignore: use_build_context_synchronously
      Navigator.of(dialogContext).pop();
      if (mounted) {
        _showExportSnackBar(filePath, isText: true);
      }
    }
  }

  // Method to handle clearing meeting data
  void _handleClearData(int meetingId) {
    // Using unawaited Future to avoid BuildContext warnings
    _clearData(meetingId);
  }

  // Async implementation without BuildContext
  Future<void> _clearData(int meetingId) async {
    if (!mounted) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('clear_data'.tr),
            content: Text('clear_data_confirm'.tr),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('confirm'.tr),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm && mounted) {
      await Get.find<MeetingController>().clearMeetingData(meetingId);
    }
  }

  // Method to handle deleting meeting
  void _handleDeleteMeeting(int meetingId) {
    // Using unawaited Future to avoid BuildContext warnings
    _deleteMeeting(meetingId);
  }

  // Async implementation without BuildContext
  Future<void> _deleteMeeting(int meetingId) async {
    if (!mounted) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('delete_meeting'.tr),
            content: Text('delete_meeting_confirm'.tr),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('confirm'.tr),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm && mounted) {
      await Get.find<MeetingController>().deleteMeeting(meetingId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MeetingController>();

    return AlertDialog(
      title: Text('meeting_history'.tr),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 新建会议按钮
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text('new_meeting'.tr),
              onTap: () {
                // Store context before any async operation
                final currentContext = context;
                // Close the current dialog
                Navigator.of(currentContext).pop();
                // Show the new meeting dialog
                showDialog(
                  context: currentContext,
                  builder: (dialogContext) => MeetingInfoDialog(
                    onSave: (title, objective, notes) async {
                      await controller.createNewMeeting(
                          title, objective, notes);
                    },
                  ),
                );
              },
            ),
            const Divider(),
            // 会议列表
            Flexible(
              child: Obx(() {
                final meetings = controller.meetings;
                if (meetings.isEmpty) {
                  return Center(
                    child: Text('no_meetings'.tr),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: meetings.length,
                  itemBuilder: (context, index) {
                    final meeting = meetings[index];
                    final isActive =
                        meeting.id == controller.currentMeeting?.id;
                    return ListTile(
                      leading: Icon(
                        Icons.meeting_room,
                        color: isActive ? Colors.blue : null,
                      ),
                      title: Text(meeting.title),
                      subtitle: Text(
                        meeting.objective ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDate(meeting.createdAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              if (value == 'export_audio') {
                                _handleAudioExport(meeting.id);
                              } else if (value == 'export_text') {
                                _handleTextExport(meeting.id);
                              } else if (value == 'clear') {
                                _handleClearData(meeting.id);
                              } else if (value == 'delete') {
                                _handleDeleteMeeting(meeting.id);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'export_audio',
                                child: ListTile(
                                  leading: const Icon(Icons.audio_file),
                                  title: Text('export_audio'.tr),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'export_text',
                                child: ListTile(
                                  leading: const Icon(Icons.description),
                                  title: Text('export_text'.tr),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'clear',
                                child: ListTile(
                                  leading: const Icon(Icons.cleaning_services),
                                  title: Text('clear_data'.tr),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: const Icon(Icons.delete_forever),
                                  title: Text('delete_meeting'.tr),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      selected: isActive,
                      onTap: () {
                        // Store context before any operations
                        final currentContext = context;
                        // Switch to selected meeting
                        controller.switchMeeting(meeting);
                        // Close the dialog
                        Navigator.of(currentContext).pop();
                      },
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Get.find<MeetingController>().openExportBaseFolder();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 18),
              const SizedBox(width: 4),
              Text('open_storage_dir'.tr),
            ],
          ),
        ),
        TextButton(
          onPressed: () {
            // Store context before any operations
            final currentContext = context;
            Navigator.of(currentContext).pop();
          },
          child: Text('close'.tr),
        ),
      ],
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
