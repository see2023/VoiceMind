import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/meeting_controller.dart';
import '../core/storage/models/stance.dart';
import '../core/utils/stance_colors.dart'; // 导入新的颜色工具类

class StanceManagementPanel extends StatelessWidget {
  final MeetingController controller;

  const StanceManagementPanel({
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: SizedBox(
        height: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'stance_management'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddStanceDialog(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Obx(() => ListView.builder(
                    itemCount: controller.stances.length,
                    itemBuilder: (context, index) {
                      final stance = controller.stances[index];
                      return _buildStanceItem(stance);
                    },
                  )),
            ),
          ],
        ),
      ),
    );
  }

  // 构建派别项
  Widget _buildStanceItem(Stance stance) {
    final stanceColor = StanceColors.getStanceColor(stance.id);
    final stanceTextColor = StanceColors.getTextColor(stanceColor);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      color: stanceColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          children: [
            // 派别名称
            InkWell(
              onTap: () => _showEditStanceDialog(stance),
              child: Text(
                stance.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: stanceTextColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 成员列表
            Expanded(
              child: Obx(() {
                final participants = controller.participants
                    .where((p) => p.stanceId == stance.id)
                    .toList();

                if (participants.isEmpty) {
                  return Text(
                    'no_participants'.tr,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: stanceTextColor.withAlpha(179),
                    ),
                  );
                }

                return Wrap(
                  spacing: 4.0,
                  runSpacing: 4.0,
                  children: participants.map((participant) {
                    final user = controller.users
                        .firstWhere((u) => u.id == participant.userId);
                    final memberBgColor = StanceColors.getMemberBackgroundColor(
                        stance.id, user.id);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 2.0,
                      ),
                      decoration: BoxDecoration(
                        color: memberBgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: stanceColor.withAlpha(80),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: stanceTextColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () =>
                                controller.removeParticipant(participant.id),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: stanceTextColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              }),
            ),
            // 操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon:
                      Icon(Icons.person_add, size: 20, color: stanceTextColor),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => _showAddParticipantDialog(stance.id),
                ),
                IconButton(
                  icon: Icon(Icons.delete, size: 20, color: stanceTextColor),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => controller.deleteStance(stance.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 添加派别对话框
  void _showAddStanceDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: Text('add_stance'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'stance_name'.tr,
              ),
            ),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: 'stance_description'.tr,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              controller.createStance(
                nameController.text,
                descriptionController.text.isEmpty
                    ? null
                    : descriptionController.text,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 添加参与者对话框
  void _showAddParticipantDialog(int stanceId) {
    Get.dialog(
      AlertDialog(
        title: Text('add_participant'.tr),
        content: SizedBox(
          width: 300,
          child: Obx(() {
            // 过滤掉已经在此派别的用户
            final availableUsers = controller.users.where((user) {
              final participant = controller.participants
                  .firstWhereOrNull((p) => p.userId == user.id);
              return participant == null || participant.stanceId != stanceId;
            }).toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...availableUsers.map((user) => ListTile(
                      title: Text(user.name),
                      subtitle: _buildParticipantSubtitle(user.id),
                      onTap: () {
                        controller.addParticipant(user.id, stanceId);
                        Get.back();
                      },
                    )),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text('add_new_user'.tr),
                  onTap: () => _showAddUserDialog(),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // 添加新用户对话框
  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final stanceId = RxInt(-1); // 使用 RxInt 来跟踪选中的派别

    Get.dialog(
      AlertDialog(
        title: Text('add_new_user'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'user_name'.tr,
              ),
            ),
            const SizedBox(height: 16),
            Obx(() => DropdownButtonFormField<int>(
                  value: stanceId.value >= 0 ? stanceId.value : null,
                  items: [
                    DropdownMenuItem(
                      value: -1,
                      child: Text('no_stance'.tr),
                    ),
                    ...controller.stances.map((stance) {
                      return DropdownMenuItem(
                        value: stance.id.toInt(),
                        child: Text(stance.name),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      stanceId.value = value;
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'initial_stance'.tr,
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              await controller.createUser(
                nameController.text,
                initialStanceId: stanceId.value >= 0 ? stanceId.value : null,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 构建参与者当前派别信息
  Widget? _buildParticipantSubtitle(int userId) {
    final participant =
        controller.participants.firstWhereOrNull((p) => p.userId == userId);
    if (participant == null || participant.stanceId == null) {
      return null;
    }

    final stance = controller.stances
        .firstWhereOrNull((s) => s.id == participant.stanceId);
    return Text('当前派别: ${stance?.name ?? "无"}');
  }

  // 添加编辑派别对话框
  void _showEditStanceDialog(Stance stance) {
    final nameController = TextEditingController(text: stance.name);
    final descriptionController =
        TextEditingController(text: stance.description);

    Get.dialog(
      AlertDialog(
        title: Text('edit_stance'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'stance_name'.tr,
              ),
            ),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: 'stance_description'.tr,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              controller.updateStance(
                stance.id,
                nameController.text,
                descriptionController.text.isEmpty
                    ? null
                    : descriptionController.text,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }
}
