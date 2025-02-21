import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/settings_controller.dart';
import '../controllers/recording_controller.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _controller = Get.find<SettingsController>();
  late TextEditingController _urlController;
  late String _selectedLanguage;
  late bool _enablePreview;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _controller.socketUrl);
    _selectedLanguage = _controller.language;
    _enablePreview = _controller.enablePreview;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    try {
      await _controller.setLanguage(_selectedLanguage);
      await _controller.setSocketUrl(_urlController.text);
      await _controller.setEnablePreview(_enablePreview);

      // 重新初始化 socket 连接
      await Get.find<RecordingController>().reinitializeSocket();

      Get.back();
      Get.snackbar(
        'success'.tr,
        'settings_saved'.tr,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 1),
      );
    } catch (e) {
      Get.snackbar(
        'error'.tr,
        'settings_save_failed'.tr,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('settings'.tr),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 350,
          maxWidth: 450,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 语言设置
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'language'.tr,
              ),
              value: _selectedLanguage,
              items: const [
                DropdownMenuItem(
                  value: 'zh_CN',
                  child: Text('中文'),
                ),
                DropdownMenuItem(
                  value: 'en_US',
                  child: Text('English'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedLanguage = value);
                }
              },
            ),
            const SizedBox(height: 16),
            // 服务器地址设置
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'server_address'.tr,
                hintText: 'localhost:9000',
              ),
            ),
            const SizedBox(height: 16),
            // 预览设置
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('enable_preview'.tr),
              value: _enablePreview,
              onChanged: (value) {
                setState(() => _enablePreview = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: _saveSettings,
          child: Text('save'.tr),
        ),
      ],
    );
  }
}
