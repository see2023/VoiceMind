import '../storage/models/proposition.dart';
import '../storage/models/proposition_stance.dart';
import '../storage/models/utterance.dart';
import '../storage/services/isar_service.dart';
import '../utils/logger.dart';
import '../../controllers/meeting_controller.dart';
import 'dart:convert';

// 用于 AI 分析的数据类型
class StanceAnalysis {
  final String userName;
  final String stanceName;
  final String type;
  final String? evidence;

  StanceAnalysis({
    required this.userName,
    required this.stanceName,
    required this.type,
    this.evidence,
  });

  Map<String, dynamic> toJson() => {
        "user_name": userName,
        "stance_name": stanceName,
        "type": type,
        "evidence": evidence,
      };
}

class PropositionAnalysis {
  final int index;
  final String content;
  final String? note;
  final List<StanceAnalysis> stances;

  PropositionAnalysis({
    required this.index,
    required this.content,
    this.note,
    required this.stances,
  });

  Map<String, dynamic> toJson({bool includeNote = true}) => {
        "index": index,
        "content": content,
        if (includeNote) "note": note,
        "stances": stances.map((s) => s.toJson()).toList(),
      };
}

class AnalysisService {
  final MeetingController meetingController;

  AnalysisService(this.meetingController);

  // 获取派别和用户关系信息
  Future<String> _getStanceUserInfo() async {
    final currentMeeting = meetingController.currentMeeting!;

    // 使用 IsarService 的方法获取派别和用户信息
    final stanceInfo = await IsarService.getStanceUsersInfo(currentMeeting.id);

    // 转换为多行字符串格式
    return stanceInfo
        .map((stance) =>
            "${stance['name']}: ${(stance['users'] as List).join(', ')}")
        .join('\n');
  }

  // 生成分析提示词
  Future<(String, String)> buildPrompts(List<Utterance> newDialogs) async {
    final currentMeeting = meetingController.currentMeeting;
    if (currentMeeting == null) throw Exception('No active meeting');

    // 构建请求数据
    final request = await _buildAnalysisRequest(newDialogs);
    final stanceInfo = await _getStanceUserInfo();

    // 获取每个对话的说话人名字
    final dialogContents = await Future.wait(
      newDialogs.map((d) async {
        final speakerName = await IsarService.getUtteranceSpeakerName(d);
        return '$speakerName: ${d.text}';
      }),
    );

    final systemPrompt = '''
你是一个智能助手，负责实时分析各方的发言并提供建议，主要职责包括：
1. 自动纠正语音识别(ASR)可能的错误
2. 根据会议/讨论的目标和背景，分析各方观点
3. 识别新的观点和立场变化
4. 为每个观点提供具体的建议和改进方向

目标：${currentMeeting.objective ?? "未设置"}
说明：${currentMeeting.notes ?? "未设置"}

规则：
1. 对已有观点：
   - 使用 index 标识
   - 可以更新观点内容，使其更准确或完整
   - 更新相关人员的立场和论据
   - 必须提供具体的建议（存储在 note 字段）
2. 对新观点：
   - 放在 new_propositions 数组中
   - 需要包含支持或反对的论据
   - 必须提供具体的建议（存储在 note 字段）
3. 建议要求：
   - 针对每个观点提供具体、可执行的建议
   - 考虑各方立场，给出平衡的建议
   - 建议应该有助于达成会议目标
4. 返回必须是合法的 JSON 格式
''';

    final userPrompt = '''
当前派别和成员：
$stanceInfo

当前观点和立场：
${jsonEncode(request)}

新增对话内容：
${dialogContents.join('\n')}

请分析上述内容，以JSON格式返回结果：
{
  "proposition_updates": [  // 已有观点的更新
    {
      "index": 1,  // 对应输入中的观点序号
      "content": "简单总结对话中反应的观点内容（修正ASR错误，使表述更准确）",
      "note": "针对该观点的具体建议，考虑各方立场，提供可执行的改进方向",
      "stances": [
        {
          "user_name": "original user_name from input",  // 必须是已有的用户名
          "stance_name": "original stance_name from input",  // 必须是已有的派别名
          "type": "support",  // support/oppose/neutral
          "evidence": "支持的具体论据，从对话中提取"
        }
      ]
    }
  ],
  "new_propositions": [  // 新观点
    {
      "content": "新的观点内容",
      "note": "针对该观点的具体建议，考虑各方立场，提供可执行的改进方向",
      "stances": [
        {
          "user_name": "",  // 必须是已有的用户名
          "stance_name": "",  // 必须是已有的派别名
          "type": "support",  // support/oppose/neutral
          "evidence": ""
        }
      ]
    }
  ]
}
''';

    return (systemPrompt, userPrompt);
  }

  // 获取当前所有主张的分析信息
  Future<List<PropositionAnalysis>> _getPropositionAnalyses() async {
    final currentMeeting = meetingController.currentMeeting!;
    final propositions =
        await IsarService.getPropositionsByMeeting(currentMeeting.id);

    return Future.wait(
      propositions.map((prop) async {
        final stanceMap = await IsarService.getPropositionStances(prop.id);

        final stanceAnalyses = await Future.wait(
          stanceMap.values.map((stance) async {
            final user = await IsarService.getUser(stance.userId);
            final stanceGroup = await IsarService.getStance(prop.stanceId);

            return StanceAnalysis(
              userName: user?.name ?? "未知",
              stanceName: stanceGroup?.name ?? "未知",
              type: stance.type.name,
              evidence: stance.evidence,
            );
          }),
        );

        return PropositionAnalysis(
          index: propositions.indexOf(prop) + 1,
          content: prop.content,
          note: prop.note,
          stances: stanceAnalyses,
        );
      }),
    );
  }

  // 构建分析请求数据
  Future<Map<String, dynamic>> _buildAnalysisRequest(
      List<Utterance> newDialogs) async {
    final propositionList = await _getPropositionAnalyses();
    return {
      "propositions":
          propositionList.map((p) => p.toJson(includeNote: false)).toList(),
    };
  }

  // 处理 AI 返回的分析结果
  Future<void> handleAnalysisResponse(Map<String, dynamic> response) async {
    final currentMeeting = meetingController.currentMeeting;
    if (currentMeeting == null) return;

    // 1. 处理已有观点的更新
    final updates = (response['proposition_updates'] as List?) ?? [];
    for (var update in updates) {
      final index = update['index'] as int;
      final propositions =
          await IsarService.getPropositionsByMeeting(currentMeeting.id);

      if (index <= propositions.length) {
        final proposition = propositions[index - 1];

        // 更新主张内容和建议（如果有）
        if (update['content'] != null || update['note'] != null) {
          final updatedProposition = proposition.copyWith(
            content: update['content'] as String? ?? proposition.content,
            note: update['note'] as String? ?? proposition.note,
          );
          await IsarService.updateProposition(updatedProposition);
        }

        // 处理每个新的立场
        final stances = (update['stances'] as List?) ?? [];
        for (var stance in stances) {
          if (stance is Map) {
            await _tryAddPropositionStance(
              proposition.id,
              stance['user_name'] as String,
              stance['stance_name'] as String,
              stance['type'] as String,
              stance['evidence'] as String?,
            );
          }
        }
      }
    }

    // 2. 处理新观点
    final newPropositions = (response['new_propositions'] as List?) ?? [];
    for (var prop in newPropositions) {
      if (prop is Map) {
        final proposition = Proposition.create(
          meetingId: currentMeeting.id,
          content: prop['content'] as String,
          note: prop['note'] as String?,
          stanceId: 0, // 默认无派别
        );

        final propId = await IsarService.createProposition(proposition);

        // 处理新观点的立场
        final stances = (prop['stances'] as List?) ?? [];
        for (var stance in stances) {
          if (stance is Map) {
            await _tryAddPropositionStance(
              propId,
              stance['user_name'] as String,
              stance['stance_name'] as String,
              stance['type'] as String,
              stance['evidence'] as String?,
            );
          }
        }
      }
    }
  }

  // 尝试添加立场（包含验证）
  Future<void> _tryAddPropositionStance(
    int propositionId,
    String userName,
    String stanceName,
    String type,
    String? evidence,
  ) async {
    try {
      // 1. 验证用户是否存在
      final user = await IsarService.getUserByName(userName);
      if (user == null) {
        Log.log.warning('User not found: $userName, skipping stance update');
        return;
      }

      // 2. 验证派别是否存在
      final stance = await IsarService.getStanceByName(
          stanceName, meetingController.currentMeeting!.id);
      if (stance == null) {
        Log.log
            .warning('Stance not found: $stanceName, skipping stance update');
        return;
      }

      // 3. 创建新的立场
      final propositionStance = PropositionStance(
        meetingId: meetingController.currentMeeting!.id,
        propositionId: propositionId,
        userId: user.id,
        type: StanceType.values.byName(type),
        evidence: evidence,
        timestamp: DateTime.now(),
      );

      await IsarService.createPropositionStance(propositionStance);
      Log.log.info(
          'Added stance for user: $userName on proposition: $propositionId');
    } catch (e) {
      Log.log.warning('Failed to add stance: $e');
    }
  }
}
