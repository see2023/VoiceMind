import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/recording_controller.dart';
import '../widgets/meeting_info_dialog.dart';
import '../widgets/meeting_history_dialog.dart';
import 'document_screen.dart';

class ControlPanel extends GetView<RecordingController> {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          _buildRecordingControl(),
          _buildMeetingInfo(),
          _buildResourcesSection(),
        ],
      ),
    );
  }

  Widget _buildMeetingInfo() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Obx(() {
        final meeting = controller.currentMeeting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(meeting?.title ?? 'untitled_meeting'.tr),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  showDialog(
                    context: Get.context!,
                    builder: (context) => MeetingInfoDialog(
                      meeting: meeting,
                      onSave: (title, objective, notes) {
                        controller.updateMeetingInfo(title, objective, notes);
                      },
                    ),
                  );
                },
                tooltip: 'edit_meeting_info'.tr,
              ),
            ),
            if (meeting?.objective != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'objective'.tr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      meeting!.objective!,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            if (meeting?.notes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'important_notes'.tr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      meeting!.notes!,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _buildRecordingControl() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Obx(() => Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.mic),
                onPressed: controller.toggleRecording,
                style: IconButton.styleFrom(
                  backgroundColor:
                      controller.isRecording ? Colors.red.withAlpha(26) : null,
                  foregroundColor: controller.isRecording ? Colors.red : null,
                ),
                tooltip: controller.isRecording
                    ? 'stop_recording'.tr
                    : 'start_recording'.tr,
              ),
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () {
                  showDialog(
                    context: Get.context!,
                    builder: (context) => const MeetingHistoryDialog(),
                  );
                },
                tooltip: 'meeting_history'.tr,
              ),
            ],
          )),
    );
  }

  Widget _buildResourcesSection() {
    return SizedBox(
      height: 200,
      child: Card(
        margin: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                'resources'.tr,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: Text('documents'.tr),
                    subtitle: Text('manage_documents_desc'.tr),
                    onTap: () {
                      Get.to(() => DocumentScreen());
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
