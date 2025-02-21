import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PromptPreviewDialog extends StatelessWidget {
  final String systemPrompt;
  final String userPrompt;

  const PromptPreviewDialog({
    super.key,
    required this.systemPrompt,
    required this.userPrompt,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('preview_prompt'.tr),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('system_prompt'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              systemPrompt,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text('user_prompt'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              userPrompt,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('confirm'.tr),
        ),
      ],
    );
  }
}
