import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/meeting_controller.dart';
import '../core/storage/models/proposition.dart';
import '../core/storage/models/proposition_stance.dart';
import '../core/storage/models/user.dart';
import '../core/utils/logger.dart';
import '../core/utils/stance_colors.dart';

class PropositionAnalysisPanel extends StatelessWidget {
  final MeetingController controller;

  const PropositionAnalysisPanel({
    required this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'proposition_analysis'.tr,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => controller.refreshAll(),
                      tooltip: 'refresh'.tr,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _showAddPropositionDialog(),
                      tooltip: 'add_proposition'.tr,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() => ListView.builder(
                  itemCount: controller.propositions.length,
                  itemBuilder: (context, index) {
                    final proposition = controller.propositions[index];
                    return _buildPropositionItem(proposition);
                  },
                )),
          ),
        ],
      ),
    );
  }

  // 添加主张对话框
  void _showAddPropositionDialog() {
    final contentController = TextEditingController();
    final noteController = TextEditingController();
    final selectedStanceId =
        RxInt(controller.stances.firstOrNull?.id.toInt() ?? -1);

    Get.dialog(
      AlertDialog(
        title: Text('add_proposition'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => DropdownButtonFormField<int>(
                  value: selectedStanceId.value >= 0
                      ? selectedStanceId.value
                      : null,
                  items: controller.stances.map((stance) {
                    return DropdownMenuItem(
                      value: stance.id.toInt(),
                      child: Text(stance.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      selectedStanceId.value = value;
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'stance'.tr,
                  ),
                )),
            TextField(
              controller: contentController,
              decoration: InputDecoration(
                labelText: 'proposition_content'.tr,
              ),
              maxLines: 3,
            ),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'proposition_note'.tr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              if (selectedStanceId.value < 0) return;
              await controller.createProposition(
                contentController.text,
                selectedStanceId.value,
                note: noteController.text.isEmpty ? null : noteController.text,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 构建主张项
  Widget _buildPropositionItem(Proposition proposition) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: InkWell(
        onDoubleTap: () => _showEditPropositionDialog(proposition),
        child: ExpansionTile(
          title: Text(proposition.content),
          subtitle: proposition.note != null
              ? Container(
                  margin: const EdgeInsets.only(top: 8.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 250, 235), // 温暖的米黄色背景
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: const Color.fromARGB(255, 255, 191, 0), // 金色边框
                      width: 1.0,
                    ),
                  ),
                  child: SelectableText(
                    proposition.note!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600, // 加粗一点
                      color: Color.fromARGB(255, 89, 61, 0), // 深褐色文字
                      height: 1.5,
                    ),
                  ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add_comment),
                onPressed: () => _showAddStanceDialog(proposition),
                tooltip: 'add_stance_opinion'.tr,
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _showDeletePropositionDialog(proposition),
                tooltip: 'delete_proposition'.tr,
              ),
            ],
          ),
          children: [
            _buildPropositionStances(proposition),
          ],
        ),
      ),
    );
  }

  String _getStanceTypeText(StanceType type) {
    switch (type) {
      case StanceType.support:
        return 'support'.tr;
      case StanceType.oppose:
        return 'oppose'.tr;
      case StanceType.neutral:
        return 'neutral'.tr;
      case StanceType.uncertain:
        return 'uncertain'.tr;
    }
  }

  // 编辑主张对话框
  void _showEditPropositionDialog(Proposition proposition) {
    final contentController = TextEditingController(text: proposition.content);
    final noteController = TextEditingController(text: proposition.note);

    Get.dialog(
      AlertDialog(
        title: Text('edit_proposition'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentController,
              decoration: InputDecoration(
                labelText: 'proposition_content'.tr,
              ),
              maxLines: 3,
            ),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'proposition_note'.tr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              await controller.updateProposition(
                proposition.id,
                content: contentController.text,
                note: noteController.text.isEmpty ? null : noteController.text,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 添加立场观点对话框
  void _showAddStanceDialog(Proposition proposition) {
    final evidenceController = TextEditingController();
    final noteController = TextEditingController();
    final selectedType = Rx<StanceType>(StanceType.neutral);
    final selectedUserId = RxInt(-1);

    Get.dialog(
      AlertDialog(
        title: Text('add_stance_opinion'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => DropdownButtonFormField<int>(
                  value:
                      selectedUserId.value >= 0 ? selectedUserId.value : null,
                  items: [
                    DropdownMenuItem(
                      value: controller.currentUser?.id,
                      child: Text(
                          '${controller.currentUser?.name} (${'current_user'.tr})'),
                    ),
                    ...controller.users
                        .where((u) => u.id != controller.currentUser?.id)
                        .map((user) {
                      return DropdownMenuItem(
                        value: user.id,
                        child: Text(user.name),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      selectedUserId.value = value;
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'select_user'.tr,
                  ),
                )),
            const SizedBox(height: 16),
            DropdownButtonFormField<StanceType>(
              value: selectedType.value,
              items: StanceType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getStanceTypeText(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  selectedType.value = value;
                }
              },
              decoration: InputDecoration(
                labelText: 'stance_type'.tr,
              ),
            ),
            TextField(
              controller: evidenceController,
              decoration: InputDecoration(
                labelText: 'stance_evidence'.tr,
              ),
              maxLines: 3,
            ),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'stance_note'.tr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              if (selectedUserId.value < 0) {
                Get.snackbar(
                  'error'.tr,
                  'please_select_user'.tr,
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }

              await controller.addPropositionStance(
                propositionId: proposition.id,
                userId: selectedUserId.value,
                type: selectedType.value,
                evidence: evidenceController.text.isEmpty
                    ? null
                    : evidenceController.text,
                note: noteController.text.isEmpty ? null : noteController.text,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 删除主张确认对话框
  void _showDeletePropositionDialog(Proposition proposition) {
    Get.dialog(
      AlertDialog(
        title: Text('delete_proposition'.tr),
        content: Text('delete_proposition_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              await controller.deleteProposition(proposition.id);
              Get.back();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 构建主张立场列表
  Widget _buildPropositionStances(Proposition proposition) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stance_opinions'.tr,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 使用 GetX 而不是 Obx 来确保响应式更新
          GetX<MeetingController>(
            builder: (controller) {
              Log.log.info(
                  'Building stance list for proposition ${proposition.id}');

              final stances = controller.propositionStances[proposition.id];
              Log.log.info(
                  'Found ${stances?.length ?? 0} stances for proposition ${proposition.id}');

              if (stances == null || stances.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'no_stance_opinions'.tr,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stances.length,
                itemBuilder: (context, index) {
                  final entry = stances.entries.elementAt(index);
                  final userId = entry.key;
                  final stance = entry.value;
                  final user = controller.users.firstWhere(
                    (u) => u.id == userId,
                    orElse: () => User(name: 'Unknown User'),
                  );

                  // 获取用户所属的派别
                  final participant = controller.participants
                      .firstWhereOrNull((p) => p.userId == userId);
                  final stanceId = participant?.stanceId;

                  // 使用相同的颜色计算逻辑
                  final backgroundColor = (stanceId != null)
                      ? StanceColors.getMemberBackgroundColor(stanceId, userId)
                      : Colors.grey[100]!;
                  final textColor = StanceColors.getTextColor(backgroundColor);

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Row(
                        children: [
                          Text(
                            user.name,
                            style: TextStyle(color: textColor),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            backgroundColor:
                                _getStanceTypeColor(stance.type).withAlpha(100),
                            labelStyle: const TextStyle(color: Colors.white),
                            label: Text(_getStanceTypeText(stance.type)),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (stance.evidence?.isNotEmpty == true)
                            Text(
                              '${'stance_evidence'.tr}: ${stance.evidence}',
                              style: TextStyle(color: textColor.withAlpha(100)),
                            ),
                          if (stance.note?.isNotEmpty == true)
                            Text(
                              '${'stance_note'.tr}: ${stance.note}',
                              style: TextStyle(color: textColor.withAlpha(100)),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.edit, color: textColor),
                        onPressed: () => _showEditStanceDialog(
                          proposition.id,
                          userId,
                          stance,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // 编辑立场观点对话框
  void _showEditStanceDialog(
    int propositionId,
    int userId,
    PropositionStance stance,
  ) {
    final evidenceController = TextEditingController(text: stance.evidence);
    final noteController = TextEditingController(text: stance.note);
    final selectedType = Rx<StanceType>(stance.type);

    Get.dialog(
      AlertDialog(
        title: Text('edit_stance'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<StanceType>(
              value: selectedType.value,
              items: StanceType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getStanceTypeText(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  selectedType.value = value;
                }
              },
              decoration: InputDecoration(
                labelText: 'stance_type'.tr,
              ),
            ),
            TextField(
              controller: evidenceController,
              decoration: InputDecoration(
                labelText: 'stance_evidence'.tr,
              ),
              maxLines: 3,
            ),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'stance_note'.tr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              await controller.updatePropositionStance(
                propositionId: propositionId,
                userId: userId,
                type: selectedType.value,
                evidence: evidenceController.text.isEmpty
                    ? null
                    : evidenceController.text,
                note: noteController.text.isEmpty ? null : noteController.text,
              );
              Get.back();
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  // 获取立场类型对应的颜色
  Color _getStanceTypeColor(StanceType type) {
    switch (type) {
      case StanceType.support:
        return Colors.green;
      case StanceType.oppose:
        return Colors.red;
      case StanceType.neutral:
        return Colors.blue;
      case StanceType.uncertain:
        return Colors.orange;
    }
  }
}
