import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/analysis_controller.dart';
import 'settings_dialog.dart';

class AnalysisSettingsPanel extends StatelessWidget {
  const AnalysisSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final analysisController = Get.find<AnalysisController>();

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: analysisController.analyzeAndSuggest,
              icon: const Icon(Icons.summarize),
              label: Text('analyze_conversation'.tr),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const SettingsDialog(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
