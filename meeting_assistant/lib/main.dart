import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/main_screen.dart';
import 'core/storage/services/isar_service.dart';
import 'controllers/meeting_controller.dart';
import 'controllers/recording_controller.dart';
import 'package:get_storage/get_storage.dart';
import 'core/i18n/translations.dart';
import 'controllers/settings_controller.dart';
import 'controllers/analysis_controller.dart';
import 'controllers/audio_player_controller.dart';
import 'dart:io';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器（仅桌面平台）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.maximize();
    });
  }

  // 初始化存储
  await GetStorage.init();

  // 初始化控制器
  final settingsController = Get.put(SettingsController());

  // 初始化 Isar
  await IsarService.initialize();

  // 初始化其他控制器
  final meetingController = Get.put(MeetingController());
  await meetingController.initializeComplete;
  Get.put(RecordingController());
  Get.put(AnalysisController());

  // 注册音频播放控制器
  Get.put(AudioPlayerController());

  // 创建应用实例
  final app = GetMaterialApp(
    translations: Messages(),
    locale: Locale(settingsController.language.split('_')[0],
        settingsController.language.split('_')[1]),
    fallbackLocale: const Locale('zh', 'CN'),
    title: 'app_title'.tr,
    theme: ThemeData(
      primarySwatch: Colors.blue,
      useMaterial3: true,
    ),
    home: const MainScreen(),
  );

  runApp(app);
}
