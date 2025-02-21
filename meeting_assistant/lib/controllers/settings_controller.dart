import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'dart:ui';
import '../core/socket/socket_config.dart';
import '../core/utils/logger.dart';

class SettingsController extends GetxController {
  static const String _socketUrlKey = 'socket_url';
  static const String _languageKey = 'language';
  static const String _enablePreviewKey = 'enable_preview';

  // 默认值
  static const String defaultSocketUrl = 'localhost:9000';
  static const String defaultLanguage = 'zh_CN';
  static const bool defaultEnablePreview = true;

  final _storage = GetStorage();
  final RxString _socketUrl = ''.obs;
  final RxString _language = ''.obs;
  final RxBool _enablePreview = true.obs;

  String get socketUrl => _socketUrl.value;
  String get language => _language.value;
  bool get enablePreview => _enablePreview.value;

  @override
  void onInit() {
    super.onInit();
    // 从存储加载配置，如果没有则使用默认值
    _socketUrl.value = _storage.read(_socketUrlKey) ?? defaultSocketUrl;
    _language.value = _storage.read(_languageKey) ?? defaultLanguage;
    _enablePreview.value =
        _storage.read(_enablePreviewKey) ?? defaultEnablePreview;

    Log.log.info(
        'Settings initialized - URL: ${_socketUrl.value}, Language: ${_language.value}, Preview: ${_enablePreview.value}');

    // 初始化时同步到 SocketConfig
    SocketConfig.baseUrl = _socketUrl.value;
  }

  Future<void> setSocketUrl(String url) async {
    _socketUrl.value = url;
    SocketConfig.baseUrl = url;
    await _storage.write(_socketUrlKey, url);
    Log.log.info('Server URL changed to: $url');
  }

  Future<void> setLanguage(String lang) async {
    _language.value = lang;
    await _storage.write(_languageKey, lang);
    Get.updateLocale(Locale(lang));
    Log.log.info('Language changed to: $lang');
  }

  Future<void> setEnablePreview(bool enable) async {
    _enablePreview.value = enable;
    await _storage.write(_enablePreviewKey, enable);
    Log.log.info('Preview enabled: $enable');
  }
}
