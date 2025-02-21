import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/storage/models/meeting.dart';

class MeetingInfoDialog extends StatefulWidget {
  final Meeting? meeting;
  final Function(String title, String? objective, String? notes) onSave;

  const MeetingInfoDialog({
    super.key,
    this.meeting,
    required this.onSave,
  });

  @override
  State<MeetingInfoDialog> createState() => _MeetingInfoDialogState();
}

class _MeetingInfoDialogState extends State<MeetingInfoDialog> {
  late TextEditingController _titleController;
  late TextEditingController _objectiveController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.meeting?.title);
    _objectiveController =
        TextEditingController(text: widget.meeting?.objective);
    _notesController = TextEditingController(text: widget.meeting?.notes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _objectiveController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('meeting_info'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'meeting_title'.tr,
                hintText: 'meeting_title_hint'.tr,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _objectiveController,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                labelText: 'meeting_objective'.tr,
                hintText: 'meeting_objective_hint'.tr,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                labelText: 'meeting_notes'.tr,
                hintText: 'meeting_notes_hint'.tr,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: () {
            widget.onSave(
              _titleController.text,
              _objectiveController.text,
              _notesController.text,
            );
            Navigator.of(context).pop();
          },
          child: Text('save'.tr),
        ),
      ],
    );
  }
}
