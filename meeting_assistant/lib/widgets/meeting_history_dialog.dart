import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/meeting_controller.dart';
import 'meeting_info_dialog.dart';

class MeetingHistoryDialog extends StatelessWidget {
  const MeetingHistoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MeetingController>();

    // 确认对话框
    Future<bool> showConfirmDialog(String title, String content) async {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('confirm'.tr),
                ),
              ],
            ),
          ) ??
          false;
    }

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
              onTap: () async {
                Navigator.of(context).pop();
                showDialog(
                  context: context,
                  builder: (context) => MeetingInfoDialog(
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
                            onSelected: (value) async {
                              if (value == 'clear') {
                                final confirm = await showConfirmDialog(
                                  'clear_data'.tr,
                                  'clear_data_confirm'.tr,
                                );
                                if (confirm) {
                                  await controller.clearMeetingData(meeting.id);
                                }
                              } else if (value == 'delete') {
                                final confirm = await showConfirmDialog(
                                  'delete_meeting'.tr,
                                  'delete_meeting_confirm'.tr,
                                );
                                if (confirm) {
                                  await controller.deleteMeeting(meeting.id);
                                }
                              }
                            },
                            itemBuilder: (context) => [
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
                        controller.switchMeeting(meeting);
                        Navigator.of(context).pop();
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
          onPressed: () => Navigator.of(context).pop(),
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
