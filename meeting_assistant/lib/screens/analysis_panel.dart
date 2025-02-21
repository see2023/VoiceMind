import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/meeting_controller.dart';
import '../widgets/analysis_settings_panel.dart';
import '../widgets/stance_management_panel.dart';
import '../widgets/proposition_analysis_panel.dart';

class AnalysisPanel extends StatelessWidget {
  const AnalysisPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final meetingController = Get.find<MeetingController>();

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          const AnalysisSettingsPanel(),
          StanceManagementPanel(controller: meetingController),
          Expanded(
            child: PropositionAnalysisPanel(controller: meetingController),
          ),
        ],
      ),
    );
  }
}
