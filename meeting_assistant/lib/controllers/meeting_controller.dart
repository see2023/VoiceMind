import 'package:get/get.dart';
import '../core/storage/models/meeting.dart';
import '../core/storage/models/stance.dart';
import '../core/storage/models/user.dart';
import '../core/storage/models/meeting_participant.dart';
import '../core/storage/models/proposition.dart';
import '../core/storage/models/proposition_stance.dart';
import '../core/storage/models/utterance.dart';
import '../core/storage/services/isar_service.dart';
import '../core/utils/logger.dart';
import 'dart:async';
import '../core/socket/meeting_service.dart';

class MeetingController extends GetxController {
  final Rx<Meeting?> _currentMeeting = Rx<Meeting?>(null);
  Meeting? get currentMeeting => _currentMeeting.value;

  // 派别分析相关
  final RxList<Stance> _stances = <Stance>[].obs;
  List<Stance> get stances => _stances;

  final RxList<User> _users = <User>[].obs;
  List<User> get users => _users;

  final RxList<MeetingParticipant> _participants = <MeetingParticipant>[].obs;
  List<MeetingParticipant> get participants => _participants;

  final RxList<Proposition> _propositions = <Proposition>[].obs;
  List<Proposition> get propositions => _propositions;

  final RxMap<int, Map<int, PropositionStance>> _propositionStances =
      <int, Map<int, PropositionStance>>{}.obs;
  Map<int, Map<int, PropositionStance>> get propositionStances =>
      _propositionStances;

  final _initCompleter = Completer<void>();
  Future<void> get initializeComplete => _initCompleter.future;

  // 当前用户
  final Rx<User?> _currentUser = Rx<User?>(null);
  User? get currentUser => _currentUser.value;

  final _meetings = <Meeting>[].obs;
  List<Meeting> get meetings => _meetings;

  // 添加对话记录状态
  final RxList<Utterance> _utterances = <Utterance>[].obs;
  List<Utterance> get utterances => _utterances;

  // 添加分页相关状态
  final RxBool _hasMore = true.obs;
  bool get hasMore => _hasMore.value;

  final RxBool _isLoading = false.obs;
  bool get isLoading => _isLoading.value;

  // 修改分页大小常量
  static const int pageSize = 50; // 默认加载50条，每次加载更多也是50条

  @override
  void onInit() {
    super.onInit();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      Log.log.info('Starting controller initialization...');
      await loadMeetings();
      await _initializeMeeting();
      await _initializeCurrentUser();
      Log.log.info('Controller initialization completed');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to initialize controller: $e\n$stackTrace');
    }
  }

  Future<void> _initializeMeeting() async {
    try {
      // 如果没有当前会议，尝试获取最近的活跃会议
      if (_currentMeeting.value == null) {
        Meeting? meeting = await IsarService.getLatestActiveMeeting();

        if (meeting == null && _meetings.isNotEmpty) {
          // 如果没有活跃会议但有历史会议，使用最新的历史会议
          meeting = _meetings.first;
        }

        if (meeting == null) {
          // 如果完全没有会议，创建一个新的
          meeting = Meeting.create(
            title: "新会议 ${DateTime.now()}",
          );
          await IsarService.saveMeeting(meeting);
          await loadMeetings(); // 重新加载会议列表
        }

        _currentMeeting.value = meeting;
        // 通知服务器初始会议ID
        await MeetingService.switchMeeting(meeting.id);
      }

      // 加载当前会议的相关数据
      await _loadUtterances();
      await _loadStances();
      await _loadUsers();
      await _loadParticipants();
      await _loadPropositions();

      Log.log.info('Meeting initialized: ${_currentMeeting.value?.title}');
      _initCompleter.complete();
    } catch (e) {
      Log.log.severe('Failed to initialize meeting: $e');
      _initCompleter.completeError(e);
    }
  }

  // 初始化当前用户
  Future<void> _initializeCurrentUser() async {
    try {
      // 如果没有用户，创建一个默认用户
      if ((await IsarService.getAllUsers()).isEmpty) {
        Log.log.info('No users found, creating default user');
        final user = User(name: 'Default User');
        final userId = await IsarService.createUser(user);
        _currentUser.value = await IsarService.getUserById(userId);
      } else {
        // 暂时使用第一个用户作为当前用户
        Log.log.info('Loading first user as current user');
        _currentUser.value = (await IsarService.getAllUsers()).first;
      }
      Log.log.info('Current user initialized: ${_currentUser.value?.name}');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to initialize current user: $e\n$stackTrace');
    }
  }

  // 设置当前用户
  Future<void> setCurrentUser(int userId) async {
    try {
      Log.log.info('Setting current user - ID: $userId');
      final user = await IsarService.getUserById(userId);
      if (user != null) {
        _currentUser.value = user;
        Log.log.info('Current user set to: ${user.name}');
      } else {
        Log.log.warning('User not found: $userId');
      }
    } catch (e, stackTrace) {
      Log.log.severe('Failed to set current user: $e\n$stackTrace');
      rethrow;
    }
  }

  // 派别相关方法
  Future<void> _loadStances() async {
    if (_currentMeeting.value == null) return;
    _stances.value =
        await IsarService.getStancesByMeeting(_currentMeeting.value!.id);
  }

  Future<void> _loadUsers() async {
    try {
      _users.value = await IsarService.getAllUsers();
      Log.log.info('Loaded ${_users.length} users');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to load users: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<void> _loadParticipants() async {
    if (_currentMeeting.value == null) {
      Log.log.warning('Cannot load participants: no active meeting');
      return;
    }

    try {
      Log.log.info(
          'Loading participants for meeting: ${_currentMeeting.value!.id}');
      _participants.value =
          await IsarService.getParticipantsByMeeting(_currentMeeting.value!.id);
      Log.log.info('Loaded ${_participants.length} participants');
      for (var p in _participants) {
        Log.log.fine(
            'Participant - ID: ${p.id}, UserID: ${p.userId}, StanceID: ${p.stanceId}');
      }
    } catch (e, stackTrace) {
      Log.log.severe('Failed to load participants: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<void> createStance(String name, String? description) async {
    if (_currentMeeting.value == null) return;
    final stance = Stance(
      name: name,
      meetingId: _currentMeeting.value!.id,
      description: description,
    );
    await IsarService.createStance(stance);
    await _loadStances();
  }

  Future<void> deleteStance(int id) async {
    await IsarService.deleteStance(id);
    await _loadStances();
  }

  Future<void> createUser(String name, {int? initialStanceId}) async {
    try {
      Log.log.info(
          'Creating new user with name: $name, initialStanceId: $initialStanceId');
      final user = User(name: name);
      final userId = await IsarService.createUser(user);
      Log.log.info('User created with ID: $userId');

      // 自动将新用户添加为会议参与者
      if (_currentMeeting.value != null) {
        Log.log.info('Adding new user as meeting participant...');
        await addParticipant(userId, initialStanceId); // 使用传入的派别ID
        Log.log.info('User added as participant successfully');
      }

      await _loadUsers();
      Log.log.info('Users list reloaded, current count: ${_users.length}');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to create user: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<void> addParticipant(int userId, int? stanceId) async {
    if (_currentMeeting.value == null) {
      Log.log.warning('Cannot add participant: no active meeting');
      return;
    }

    try {
      Log.log.info(
          'Starting to add participant - userId: $userId, stanceId: $stanceId, meetingId: ${_currentMeeting.value!.id}');

      // 检查是否已经是参与者
      final existingParticipant = await IsarService.getParticipantByUserId(
        _currentMeeting.value!.id,
        userId,
      );

      if (existingParticipant != null) {
        Log.log.info(
            'Found existing participant: ${existingParticipant.id}, updating stance...');
        // 如果已经是参与者，更新派别
        await updateParticipantStance(existingParticipant.id, stanceId);
        Log.log.info('Existing participant updated successfully');
      } else {
        Log.log.info('No existing participant found, creating new one...');
        // 如果不是参与者，创建新的参与记录
        final participant = MeetingParticipant(
          meetingId: _currentMeeting.value!.id,
          userId: userId,
          stanceId: stanceId,
        );

        final newId = await IsarService.addParticipant(participant);
        Log.log.info('New participant created with ID: $newId');
      }

      Log.log.info('Reloading participants list...');
      await _loadParticipants();
      Log.log.info(
          'Participants list reloaded, current count: ${_participants.length}');

      // 打印当前所有参与者的信息，用于调试
      for (var p in _participants) {
        Log.log.fine(
            'Participant - ID: ${p.id}, UserID: ${p.userId}, StanceID: ${p.stanceId}');
      }
    } catch (e, stackTrace) {
      Log.log.severe('Failed to add/update participant: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<void> updateParticipantStance(int participantId, int? stanceId) async {
    await IsarService.updateParticipantStance(participantId, stanceId);
    await _loadParticipants();
  }

  Future<void> endCurrentMeeting() async {
    try {
      if (_currentMeeting.value != null) {
        await IsarService.updateMeeting(_currentMeeting.value!,
            isActive: false);
        Log.log.info('Meeting ended: ${_currentMeeting.value?.title}');
      }
    } catch (e) {
      Log.log.severe('Failed to end meeting: $e');
    }
  }

  Future<void> refreshMeeting() async {
    try {
      final meeting = await IsarService.getLatestActiveMeeting();
      _currentMeeting.value = meeting;
      Log.log.info('Meeting refreshed: ${meeting?.title}');
    } catch (e) {
      Log.log.severe('Failed to refresh meeting: $e');
    }
  }

  // 加载主张数据
  Future<void> _loadPropositions() async {
    if (_currentMeeting.value == null) return;
    try {
      Log.log.info('Loading propositions and stances...');

      // 加载所有主张
      _propositions.value =
          await IsarService.getPropositionsByMeeting(_currentMeeting.value!.id);
      Log.log.info('Loaded ${_propositions.length} propositions');

      // 创建新的 Map 实例以触发更新
      final newStances = <int, Map<int, PropositionStance>>{};

      // 加载每个主张的所有立场
      for (var prop in _propositions) {
        try {
          final stances = await IsarService.getPropositionStances(prop.id);
          newStances[prop.id] = Map<int, PropositionStance>.from(stances);
          Log.log.info(
              'Loaded ${stances.length} stances for proposition ${prop.id}');
        } catch (e, stackTrace) {
          Log.log.severe(
              'Error loading stances for proposition ${prop.id}: $e\n$stackTrace');
        }
      }

      // 一次性更新所有立场数据
      _propositionStances.value = newStances;
      Log.log.info(
          'Updated proposition stances map with ${newStances.length} entries');
    } catch (e, stackTrace) {
      Log.log
          .severe('Failed to load propositions and stances: $e\n$stackTrace');
      rethrow;
    }
  }

  // 添加公开的刷新方法
  Future<void> refreshPropositions() async {
    await _loadPropositions();
  }

  // 创建新主张
  Future<void> createProposition(
    String content,
    int stanceId, {
    String? note,
  }) async {
    if (_currentMeeting.value == null) return;

    try {
      Log.log.info('Creating new proposition...');
      final proposition = Proposition.create(
        meetingId: _currentMeeting.value!.id,
        stanceId: stanceId,
        content: content,
        note: note,
      );

      await IsarService.createProposition(proposition);
      await refreshAll();
      Log.log.info('Proposition created and data refreshed');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to create proposition: $e\n$stackTrace');
      rethrow;
    }
  }

  // 更新主张立场
  Future<void> updatePropositionStance({
    required int propositionId,
    required int userId,
    required StanceType type,
    String? evidence,
    String? note,
  }) async {
    await IsarService.updatePropositionAnalysis(
      propositionId: propositionId,
      userId: userId,
      type: type,
      evidence: evidence,
      note: note,
    );
    await _loadPropositions();
  }

  Future<void> removeParticipant(int participantId) async {
    try {
      Log.log.info('Removing participant - ID: $participantId');
      final result = await IsarService.deleteParticipant(participantId);
      if (result) {
        Log.log.info('Participant removed successfully');
        await _loadParticipants();
      } else {
        Log.log.warning('Failed to remove participant');
      }
    } catch (e, stackTrace) {
      Log.log.severe('Failed to remove participant: $e\n$stackTrace');
      rethrow;
    }
  }

  // 更新主张
  Future<void> updateProposition(
    int propositionId, {
    required String content,
    String? note,
  }) async {
    try {
      Log.log.info('Updating proposition - ID: $propositionId');
      final proposition = propositions.firstWhere((p) => p.id == propositionId);

      final updated = Proposition.create(
        meetingId: proposition.meetingId,
        stanceId: proposition.stanceId,
        content: content,
        note: note,
      );
      updated.id = propositionId;

      await IsarService.updateProposition(updated);
      await _loadPropositions();
    } catch (e, stackTrace) {
      Log.log.severe('Failed to update proposition: $e\n$stackTrace');
      rethrow;
    }
  }

  // 添加主张立场
  Future<void> addPropositionStance({
    required int propositionId,
    required int userId,
    required StanceType type,
    String? evidence,
    String? note,
  }) async {
    try {
      Log.log.info(
          'Adding proposition stance - PropositionID: $propositionId, UserID: $userId');
      final proposition = propositions.firstWhere((p) => p.id == propositionId);

      final stance = PropositionStance(
        meetingId: proposition.meetingId,
        propositionId: propositionId,
        userId: userId,
        type: type,
        evidence: evidence,
        note: note,
        timestamp: DateTime.now(),
      );

      await IsarService.createPropositionStance(stance);
      await _loadPropositions();
    } catch (e, stackTrace) {
      Log.log.severe('Failed to add proposition stance: $e\n$stackTrace');
      rethrow;
    }
  }

  // 删除主张
  Future<void> deleteProposition(int propositionId) async {
    try {
      Log.log.info('Deleting proposition - ID: $propositionId');
      await IsarService.deleteProposition(propositionId);
      await _loadPropositions();
    } catch (e, stackTrace) {
      Log.log.severe('Failed to delete proposition: $e\n$stackTrace');
      rethrow;
    }
  }

  // 添加刷新所有数据的方法
  Future<void> refreshAll() async {
    try {
      Log.log.info('Refreshing all data...');
      _utterances.clear(); // 清空当前对话记录
      await _loadUtterances(); // 加载新会议的对话记录
      await _loadStances();
      await _loadUsers();
      await _loadParticipants();
      await _loadPropositions();
      Log.log.info('All data refreshed successfully');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to refresh data: $e\n$stackTrace');
    }
  }

  // 加载所有会议列表
  Future<void> loadMeetings() async {
    try {
      _meetings.value = await IsarService.getMeetings();
      Log.log.info('Loaded ${_meetings.length} meetings');
    } catch (e) {
      Log.log.severe('Failed to load meetings: $e');
      rethrow;
    }
  }

  // 创建新会议
  Future<void> createNewMeeting(
      String title, String? objective, String? notes) async {
    try {
      Log.log.info('Creating new meeting: $title');
      final meeting = Meeting.create(
        title: title,
        objective: objective,
        notes: notes,
      );

      await IsarService.saveMeeting(meeting);
      await loadMeetings(); // 重新加载会议列表
      await switchMeeting(meeting); // 切换到新会议

      Log.log.info('New meeting created and switched to: $title');
    } catch (e) {
      Log.log.severe('Failed to create new meeting: $e');
      rethrow;
    }
  }

  // 切换会议
  Future<void> switchMeeting(Meeting meeting) async {
    try {
      Log.log.info('Switching to meeting: ${meeting.title}');

      // 如果有正在进行的会议，先结束它
      if (_currentMeeting.value != null && _currentMeeting.value!.isActive) {
        await endCurrentMeeting();
      }

      // 更新当前会议
      _currentMeeting.value = meeting;

      // 通知服务器切换会议
      await MeetingService.switchMeeting(meeting.id);

      // 重新加载所有相关数据
      await refreshAll();

      Log.log.info('Successfully switched to meeting: ${meeting.title}');
    } catch (e) {
      Log.log.severe('Failed to switch meeting: $e');
      rethrow;
    }
  }

  // 修改加载对话记录的方法，支持分页
  Future<void> _loadUtterances({bool refresh = false}) async {
    try {
      if (_currentMeeting.value == null) {
        Log.log.warning('Cannot load utterances: no active meeting');
        return;
      }

      if (_isLoading.value) return;
      _isLoading.value = true;

      final offset = refresh ? 0 : _utterances.length;
      Log.log.info(
          'Loading utterances for meeting: ${_currentMeeting.value!.id}, offset: $offset');

      final (utterances, hasMore) = await IsarService.getUtterances(
        _currentMeeting.value!.id,
        offset: offset,
        limit: pageSize,
      );

      if (refresh) {
        _utterances.clear();
      }

      if (utterances.isNotEmpty) {
        _utterances.addAll(utterances);
      }
      _hasMore.value = hasMore;

      Log.log.info(
          'Loaded ${utterances.length} utterances, total: ${_utterances.length}, hasMore: $hasMore');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to load utterances: $e\n$stackTrace');
    } finally {
      _isLoading.value = false;
    }
  }

  // 添加加载更多的方法
  Future<void> loadMoreUtterances() async {
    if (_isLoading.value || !_hasMore.value) return;

    try {
      _isLoading.value = true;
      final (utterances, hasMore) = await IsarService.getUtterances(
        currentMeeting!.id,
        offset: _utterances.length,
        limit: pageSize,
      );

      _utterances.addAll(utterances); // 添加到末尾
      _hasMore.value = hasMore;
    } finally {
      _isLoading.value = false;
    }
  }

  // 添加刷新方法
  Future<void> refreshUtterances() async {
    _hasMore.value = true;
    await _loadUtterances(refresh: true);
  }

  // 添加新的对话记录
  Future<void> addUtterance(Utterance utterance) async {
    await IsarService.saveUtterance(utterance);
    _utterances.insert(0, utterance); // 插入到开头，保持与 ListView.reverse 一致
  }

  // 更新对话记录
  Future<void> updateUtterance(Utterance utterance) async {
    final index = _utterances.indexWhere((u) => u.id == utterance.id);
    if (index >= 0) {
      await IsarService.updateUtterance(utterance);
      _utterances[index] = utterance;
    }
  }

  // 更新会议最后分析时间
  Future<void> updateMeetingLastAnalysisTime(int timestamp) async {
    if (_currentMeeting.value == null) return;

    try {
      Log.log.info('Updating meeting analysis time...');
      final updated = _currentMeeting.value!.updateAnalysisTime();
      await IsarService.saveMeeting(updated);
      _currentMeeting.value = updated;
      Log.log.info('Meeting analysis time updated');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to update meeting analysis time: $e\n$stackTrace');
      rethrow;
    }
  }

  Future<void> updateStance(
      int stanceId, String name, String? description) async {
    try {
      Log.log.info('Updating stance - ID: $stanceId, Name: $name');
      final stance = stances.firstWhere((s) => s.id == stanceId);

      final updated = Stance(
        name: name,
        meetingId: stance.meetingId,
        description: description,
      );
      updated.id = stanceId;

      await IsarService.updateStance(updated);
      await _loadStances();
      Log.log.info('Stance updated successfully');
    } catch (e, stackTrace) {
      Log.log.severe('Failed to update stance: $e\n$stackTrace');
      rethrow;
    }
  }

  // 清除会议数据
  Future<void> clearMeetingData(int meetingId) async {
    try {
      Log.log.info('Clearing data for meeting: $meetingId');
      await IsarService.clearMeetingData(meetingId);

      // 如果是当前会议,刷新数据
      if (currentMeeting?.id == meetingId) {
        await refreshAll();
      }
    } catch (e) {
      Log.log.severe('Failed to clear meeting data: $e');
      rethrow;
    }
  }

  // 删除会议
  Future<void> deleteMeeting(int meetingId) async {
    try {
      Log.log.info('Deleting meeting: $meetingId');

      // 如果要删除的是当前会议,先找到其他会议
      Meeting? otherMeeting;
      if (currentMeeting?.id == meetingId) {
        otherMeeting = meetings.firstWhereOrNull((m) => m.id != meetingId);
      }

      // 执行删除操作
      await IsarService.deleteMeeting(meetingId);

      // 删除成功后，如果需要则切换到其他会议
      if (currentMeeting?.id == meetingId && otherMeeting != null) {
        await switchMeeting(otherMeeting);
      }

      await loadMeetings(); // 重新加载会议列表
    } catch (e) {
      Log.log.severe('Failed to delete meeting: $e');
      rethrow;
    }
  }
}
