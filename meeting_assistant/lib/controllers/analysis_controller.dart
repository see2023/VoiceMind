import 'package:get/get.dart';
import '../core/assistant/analysis_service.dart';
import '../core/assistant/ai_service.dart';
import '../core/utils/logger.dart';
import '../controllers/meeting_controller.dart';
import '../core/storage/services/isar_service.dart';
import '../controllers/settings_controller.dart';
import 'package:flutter/material.dart';
import '../widgets/prompt_preview_dialog.dart';

class AnalysisController extends GetxController {
  final analysisService = AnalysisService(Get.find<MeetingController>());
  final meetingController = Get.find<MeetingController>();
  final settingsController = Get.find<SettingsController>();

  // 添加加载状态
  final RxBool isLoading = false.obs;

  // 准备分析，返回提示词
  Future<(String, String)> prepareAnalysis() async {
    final currentMeeting = meetingController.currentMeeting;
    if (currentMeeting == null) {
      throw Exception('No active meeting');
    }

    // 从数据库获取新的对话记录（最多100条）
    final newDialogs = await IsarService.getNewUtterances(
      currentMeeting.id,
      currentMeeting.lastAnalysisTime ?? 0,
    );

    if (newDialogs.isEmpty) {
      throw Exception('no_new_dialogs'.tr);
    }

    // 记录最新对话时间
    _latestDialogTime = newDialogs
        .map((d) => d.startTime)
        .reduce((max, time) => time > max ? time : max);

    // 生成提示词
    return await analysisService.buildPrompts(newDialogs);
  }

  int? _latestDialogTime;

  // 执行分析和生成建议
  Future<void> executeAnalysis(String systemPrompt, String userPrompt) async {
    try {
      isLoading.value = true;
      final response = await AIService.analyze(systemPrompt, userPrompt);
      await analysisService.handleAnalysisResponse(response);

      // 使用最新对话的时间作为分析时间点
      if (_latestDialogTime != null) {
        await meetingController
            .updateMeetingLastAnalysisTime(_latestDialogTime!);
        _latestDialogTime = null;
      }

      // 直接调用刷新方法
      await meetingController.refreshAll();
    } catch (e) {
      Log.log.severe('Failed to analyze dialogs: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  // 执行分析和建议的完整流程
  Future<void> analyzeAndSuggest() async {
    try {
      final (systemPrompt, userPrompt) = await prepareAnalysis();

      // 根据设置决定是否显示预览
      if (settingsController.enablePreview) {
        if (!Get.context!.mounted) return;

        final result = await showDialog<bool>(
          context: Get.context!,
          builder: (context) => PromptPreviewDialog(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
          ),
        );

        if (result != true) return;
      }

      // 显示进度对话框
      Get.dialog(
        const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在分析对话...'),
                  ],
                ),
              ),
            ),
          ),
        ),
        barrierDismissible: false,
      );

      await executeAnalysis(systemPrompt, userPrompt);
      Get.back(); // 关闭进度对话框

      Get.snackbar(
        'success'.tr,
        'analysis_completed'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.back(); // 确保关闭进度对话框
      Get.snackbar(
        'error'.tr,
        'analysis_failed'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
