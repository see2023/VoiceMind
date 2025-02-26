import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/meeting.dart';
import '../models/audio_chunk.dart';
import '../models/utterance.dart';
import '../models/user.dart';
import '../models/speaker.dart';
import '../models/stance.dart';
import '../models/proposition.dart';
import '../models/proposition_stance.dart';
import '../models/meeting_participant.dart';
import '../../utils/logger.dart';

class IsarService {
  static late Isar isar;

  // 缓存
  static final Map<int, String> _userNameCache = {};
  static final Map<(int, int), String> _speakerNameCache =
      {}; // (meetingId, speakerId) -> userName

  static Future<void> initialize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      isar = await Isar.open(
        [
          MeetingSchema,
          AudioChunkSchema,
          UtteranceSchema,
          UserSchema,
          SpeakerSchema,
          StanceSchema,
          PropositionSchema,
          PropositionStanceSchema,
          MeetingParticipantSchema,
        ],
        directory: dir.path,
      );
      Log.log.info('Isar initialized at ${dir.path}');
    } catch (e) {
      Log.log.severe('Failed to initialize Isar: $e');
      rethrow;
    }
  }

  // 获取最近活跃的会议
  static Future<Meeting?> getLatestActiveMeeting() async {
    return await isar.meetings.where().sortByUpdatedAtDesc().findFirst();
  }

  // 保存音频块
  static Future<void> saveAudioChunk(AudioChunk chunk) async {
    await isar.writeTxn(() async {
      await isar.audioChunks.put(chunk);
    });
  }

  // 保存语音识别结果
  static Future<void> saveUtterance(Utterance utterance) async {
    await isar.writeTxn(() async {
      // 查找是否存在相同startTime和isFinal状态的记录
      final existing = await isar.utterances
          .where()
          .meetingIdEqualTo(utterance.meetingId)
          .filter()
          .startTimeEqualTo(utterance.startTime)
          .isFinalEqualTo(utterance.isFinal)
          .findFirst();

      if (existing != null) {
        // 如果存在，复制现有记录的ID
        existing.copyWith(
          text: utterance.text,
          speakerId: utterance.speakerId,
          endTime: utterance.endTime,
          wordTimestamps: utterance.wordTimestamps,
        );
        utterance = existing;
        Log.log.finest('Updating existing utterance: ${existing.id}');
      }

      await isar.utterances.put(utterance); // 保存或更新记录
    });
  }

  // 分页获取会议的语音识别结果
  static Future<(List<Utterance>, bool)> getUtterances(
    int meetingId, {
    int offset = 0,
    int limit = 20,
  }) async {
    // 先获取总数
    final total =
        await isar.utterances.where().meetingIdEqualTo(meetingId).count();

    // 获取当前页数据
    final utterances = await isar.utterances
        .where()
        .meetingIdEqualTo(meetingId)
        .sortByStartTimeDesc()
        .offset(offset)
        .limit(limit)
        .findAll();

    // 判断是否还有更多数据
    final hasMore = offset + utterances.length < total;

    Log.log.info(
        'Fetched utterances: offset=$offset, limit=$limit, got=${utterances.length}, total=$total, hasMore=$hasMore');

    return (utterances, hasMore);
  }

  // 获取会议的语音识别结果总数
  static Future<int> getUtterancesCount(int meetingId) async {
    final count =
        await isar.utterances.where().meetingIdEqualTo(meetingId).count();
    Log.log.info('Total utterances count for meeting $meetingId: $count');
    return count;
  }

  // 获取指定时间范围的音频数据
  static Future<List<AudioChunk>> getAudioChunks(
    int meetingId,
    int startTime,
    int endTime,
  ) async {
    Log.log.info('Fetching audio chunks from $startTime to $endTime');
    final chunks = await isar.audioChunks
        .where()
        .meetingIdEqualTo(meetingId)
        .filter()
        // 往前取 200ms 的音频
        .startTimeGreaterThan(startTime - 200)
        .startTimeLessThan(endTime)
        .sortByStartTime()
        .findAll();
    Log.log.info('Found ${chunks.length} audio chunks');
    return chunks;
  }

  // 更新会议信息
  static Future<void> updateMeeting(Meeting meeting,
      {bool isActive = true}) async {
    final now = DateTime.now();
    final updatedMeeting = Meeting(
      id: meeting.id,
      title: meeting.title,
      objective: meeting.objective,
      notes: meeting.notes,
      createdAt: meeting.createdAt,
      updatedAt: now.millisecondsSinceEpoch,
      isActive: isActive,
      lastAnalysisTime: meeting.lastAnalysisTime,
    );
    await isar.writeTxn(() async {
      await isar.meetings.put(updatedMeeting);
    });
  }

  // 数据转换方法
  static Utterance? convertToUtterance(
      Map<String, dynamic> data, int meetingId) {
    try {
      // 确保数据中的 meetingId 匹配
      if (data['meetingId'] != meetingId) return null;

      // 处理 timestamp 字段
      List<int> timestamps = [];
      if (data['timestamp'] != null) {
        if (data['timestamp'] is List) {
          timestamps =
              (data['timestamp'] as List).map((e) => e as int).toList();
        } else {
          Log.log.warning('Invalid timestamp format: ${data['timestamp']}');
        }
      }

      return Utterance(
        id: data['id'] as int,
        meetingId: meetingId,
        text: data['text'] as String,
        speakerId: data['speaker_id'] as int?,
        userId: data['user_id'] as int?,
        startTime: data['start_time'] as int,
        endTime: data['end_time'] as int,
        isFinal: data['isFinal'] as bool,
        isConfirmed: data['isConfirmed'] as bool,
        note: data['note'] as String?,
        wordTimestamps: timestamps,
      );
    } catch (e) {
      Log.log.severe(
          'Failed to convert conversation to utterance: $e\nData: $data');
      return null;
    }
  }

  // 更新 Utterance
  static Future<void> updateUtterance(Utterance utterance,
      {String? text, String? note}) async {
    try {
      Log.log.fine(
          'Updating utterance: id=${utterance.id} (${utterance.id.runtimeType})');

      final updated = utterance.copyWith(
        text: text ?? utterance.text,
        note: note,
        isConfirmed: true,
      );

      Log.log.fine(
          'Updated utterance object created: id=${updated.id} (${updated.id.runtimeType})');

      await isar.writeTxn(() async {
        final result = await isar.utterances.put(updated);
        Log.log.fine('Update result: $result, original id: ${utterance.id}');
      });
    } catch (e) {
      Log.log.severe('Failed to update utterance: $e');
      rethrow;
    }
  }

  // 添加 stance 相关操作
  // 派别相关操作
  static Future<int> createStance(Stance stance) async {
    return await isar.writeTxn(() async {
      return await isar.stances.put(stance);
    });
  }

  static Future<List<Stance>> getStancesByMeeting(int meetingId) async {
    return await isar.stances.filter().meetingIdEqualTo(meetingId).findAll();
  }

  static Future<bool> deleteStance(int id) async {
    return await isar.writeTxn(() async {
      return await isar.stances.delete(id);
    });
  }

  // 用户相关操作
  static Future<int> createUser(User user) async {
    try {
      Log.log.info('Creating user in database: ${user.name}');
      return await isar.writeTxn(() async {
        final id = await isar.users.put(user);
        Log.log.info('User created in database with ID: $id');
        // 验证是否真的写入成功
        final saved = await isar.users.get(id);
        if (saved != null) {
          Log.log.info('Verified: user was saved correctly');
        } else {
          Log.log.warning('Warning: Could not verify saved user');
        }
        return id;
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to create user in database: $e\n$stackTrace');
      rethrow;
    }
  }

  static Future<List<User>> getAllUsers() async {
    try {
      final users = await isar.users.where().findAll();
      return users;
    } catch (e, stackTrace) {
      Log.log.severe('Failed to fetch users from database: $e\n$stackTrace');
      rethrow;
    }
  }

  // 参会者相关操作
  static Future<MeetingParticipant?> getParticipantByUserId(
    int meetingId,
    int userId,
  ) async {
    try {
      Log.log
          .info('Getting participant - meetingId: $meetingId, userId: $userId');
      final participant = await isar.meetingParticipants
          .filter()
          .meetingIdEqualTo(meetingId)
          .and()
          .userIdEqualTo(userId)
          .findFirst();
      Log.log.info('Found participant: ${participant?.id}');
      return participant;
    } catch (e) {
      Log.log.severe('Failed to get participant: $e');
      rethrow;
    }
  }

  static Future<int> addParticipant(MeetingParticipant participant) async {
    try {
      Log.log.info(
          'Adding participant to database - MeetingID: ${participant.meetingId}, UserID: ${participant.userId}, StanceID: ${participant.stanceId}');

      return await isar.writeTxn(() async {
        final id = await isar.meetingParticipants.put(participant);
        Log.log.info('Participant added successfully with ID: $id');

        // 验证是否真的写入成功
        final saved = await isar.meetingParticipants.get(id);
        if (saved != null) {
          Log.log.info('Verified: participant was saved correctly');
        } else {
          Log.log.warning('Warning: Could not verify saved participant');
        }

        return id;
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to add participant to database: $e\n$stackTrace');
      rethrow;
    }
  }

  static Future<List<MeetingParticipant>> getParticipantsByMeeting(
      int meetingId) async {
    try {
      final participants = await isar.meetingParticipants
          .filter()
          .meetingIdEqualTo(meetingId)
          .findAll();

      Log.log.info(
          'Found ${participants.length} participants for meeting $meetingId');

      return participants;
    } catch (e, stackTrace) {
      Log.log.severe('Failed to fetch participants: $e\n$stackTrace');
      rethrow;
    }
  }

  static Future<bool> updateParticipantStance(
      int participantId, int? stanceId) async {
    try {
      Log.log.info(
          'Updating participant stance - ID: $participantId, new StanceID: $stanceId');
      return await isar.writeTxn(() async {
        var participant = await isar.meetingParticipants.get(participantId);
        if (participant == null) {
          Log.log.warning('Participant not found: $participantId');
          return false;
        }

        Log.log.info('Found participant, updating stance...');
        // 创建新的参与者记录，保持原有ID
        participant = MeetingParticipant(
          meetingId: participant.meetingId,
          userId: participant.userId,
          stanceId: stanceId,
        );
        participant.id = participantId; // 设置原有ID

        final result = await isar.meetingParticipants.put(participant);
        Log.log.info('Participant stance updated, result: $result');

        final updated = await isar.meetingParticipants.get(participantId);
        if (updated != null) {
          Log.log.info(
              'Verified update - ID: ${updated.id}, UserID: ${updated.userId}, StanceID: ${updated.stanceId}');
        } else {
          Log.log.warning('Failed to verify update');
        }

        return true;
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to update participant stance: $e\n$stackTrace');
      rethrow;
    }
  }

  // 添加新的方法
  static Future<User?> getUserById(int userId) async {
    return await isar.users.get(userId);
  }

  static Future<Stance?> getStanceById(int stanceId) async {
    return await isar.stances.get(stanceId);
  }

  static Future<List<User>> getUsersByStance(
      int meetingId, int stanceId) async {
    final participants = await isar.meetingParticipants
        .filter()
        .meetingIdEqualTo(meetingId)
        .stanceIdEqualTo(stanceId)
        .findAll();

    final userIds = participants.map((p) => p.userId).toList();
    return await isar.users
        .where()
        .anyOf(userIds, (q, id) => q.idEqualTo(id))
        .findAll();
  }

  static Future<bool> removeParticipantFromStance(int participantId) async {
    return await updateParticipantStance(participantId, null);
  }

  static Future<bool> deleteUser(int userId) async {
    return await isar.writeTxn(() async {
      // 先删除该用户的所有参会记录
      await isar.meetingParticipants.filter().userIdEqualTo(userId).deleteAll();

      // 然后删除用户
      return await isar.users.delete(userId);
    });
  }

  static Future<bool> updateUser(User user) async {
    final result = await isar.writeTxn(() async {
      return await isar.users.put(user) > 0;
    });
    if (result) {
      _userNameCache[user.id] = user.name;
    }
    return result;
  }

  static Future<bool> updateStance(Stance stance) async {
    return await isar.writeTxn(() async {
      return await isar.stances.put(stance) > 0;
    });
  }

  static Future<int> getParticipantsCountInStance(
      int meetingId, int stanceId) async {
    return await isar.meetingParticipants
        .filter()
        .meetingIdEqualTo(meetingId)
        .stanceIdEqualTo(stanceId)
        .count();
  }

  // 主张相关操作
  static Future<int> createProposition(Proposition proposition) async {
    return await isar.writeTxn(() async {
      return await isar.propositions.put(proposition);
    });
  }

  static Future<List<Proposition>> getPropositionsByMeeting(
      int meetingId) async {
    return await isar.propositions
        .filter()
        .meetingIdEqualTo(meetingId)
        .findAll();
  }

  static Future<List<Proposition>> getPropositionsByStance(
      int meetingId, int stanceId) async {
    return await isar.propositions
        .filter()
        .meetingIdEqualTo(meetingId)
        .stanceIdEqualTo(stanceId)
        .findAll();
  }

  static Future<bool> deleteProposition(int id) async {
    return await isar.writeTxn(() async {
      // 先删除相关的立场
      await isar.propositionStances
          .filter()
          .propositionIdEqualTo(id)
          .deleteAll();
      // 然后删除主张
      return await isar.propositions.delete(id);
    });
  }

  // 主张立场相关操作
  static Future<int> createPropositionStance(
      PropositionStance propositionStance) async {
    return await isar.writeTxn(() async {
      return await isar.propositionStances.put(propositionStance);
    });
  }

  static Future<List<PropositionStance>> getPropositionStancesByUser(
      int meetingId, int userId) async {
    return await isar.propositionStances
        .filter()
        .meetingIdEqualTo(meetingId)
        .userIdEqualTo(userId)
        .findAll();
  }

  static Future<PropositionStance?> getPropositionStance(
      int propositionId, int userId) async {
    return await isar.propositionStances
        .filter()
        .propositionIdEqualTo(propositionId)
        .userIdEqualTo(userId)
        .findFirst();
  }

  static Future<bool> updatePropositionStance(
      PropositionStance propositionStance) async {
    return await isar.writeTxn(() async {
      return await isar.propositionStances.put(propositionStance) > 0;
    });
  }

  // 更新主张立场
  static Future<bool> updatePropositionAnalysis({
    required int propositionId,
    required int userId,
    required StanceType type,
    String? evidence,
    String? note,
  }) async {
    return await isar.writeTxn(() async {
      var stance = await getPropositionStance(propositionId, userId);
      if (stance == null) return false;

      stance = PropositionStance(
        meetingId: stance.meetingId,
        propositionId: propositionId,
        userId: userId,
        type: type,
        evidence: evidence ?? stance.evidence,
        note: note ?? stance.note,
        timestamp: DateTime.now(),
      );

      return await isar.propositionStances.put(stance) > 0;
    });
  }

  // 获取某个主张的所有立场
  static Future<Map<int, PropositionStance>> getPropositionStances(
      int propositionId) async {
    try {
      Log.log.info('Fetching stances for proposition: $propositionId');
      final stances = await isar.propositionStances
          .filter()
          .propositionIdEqualTo(propositionId)
          .findAll();

      Log.log.info(
          'Found ${stances.length} stances for proposition $propositionId');
      final result = {for (var stance in stances) stance.userId: stance};

      // 打印详细信息用于调试
      for (var stance in stances) {
        Log.log.fine(
            'Stance - UserID: ${stance.userId}, Type: ${stance.type}, Evidence: ${stance.evidence}');
      }

      return result;
    } catch (e, stackTrace) {
      Log.log.severe('Failed to fetch proposition stances: $e\n$stackTrace');
      rethrow;
    }
  }

  static Future<bool> deleteParticipant(int participantId) async {
    try {
      Log.log.info('Deleting participant - ID: $participantId');
      return await isar.writeTxn(() async {
        final result = await isar.meetingParticipants.delete(participantId);
        Log.log.info('Participant deleted, result: $result');
        return result;
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to delete participant: $e\n$stackTrace');
      rethrow;
    }
  }

  // 更新主张
  static Future<bool> updateProposition(Proposition proposition) async {
    try {
      Log.log.info('Updating proposition - ID: ${proposition.id}');
      return await isar.writeTxn(() async {
        final result = await isar.propositions.put(proposition);
        Log.log.info('Proposition updated, result: $result');

        // 验证更新结果
        final updated = await isar.propositions.get(proposition.id);
        if (updated != null) {
          Log.log.info(
              'Verified update - ID: ${updated.id}, Content: ${updated.content}');
        } else {
          Log.log.warning('Failed to verify proposition update');
        }

        return result > 0;
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to update proposition: $e\n$stackTrace');
      rethrow;
    }
  }

  static Future<Speaker?> getSpeaker(int meetingId, int speakerId) async {
    return await isar.speakers
        .filter()
        .meetingIdEqualTo(meetingId)
        .speakerIdEqualTo(speakerId)
        .findFirst();
  }

  static Future<User?> getUser(int userId) async {
    return await isar.users.get(userId);
  }

  static Future<Stance?> getStance(int stanceId) async {
    return await isar.stances.get(stanceId);
  }

  static Future<void> updateUtteranceUser(
    Utterance utterance,
    int? userId,
  ) async {
    await isar.writeTxn(() async {
      // 只更新 userId，保持原有的 speakerId
      final updatedUtterance = utterance.copyWith(
        userId: userId,
      );
      await isar.utterances.put(updatedUtterance);
      Log.log.info(
          'Utterance user mapping updated: id=${utterance.id}, speakerId=${utterance.speakerId}, userId=$userId');
    });
  }

  static Future<int> getNextSpeakerId(int meetingId) async {
    final maxSpeaker = await isar.speakers
        .filter()
        .meetingIdEqualTo(meetingId)
        .sortBySpeakerIdDesc()
        .findFirst();
    return (maxSpeaker?.speakerId ?? 0) + 1;
  }

  static Future<Speaker?> getSpeakerByUserId(int meetingId, int userId) async {
    return await isar.speakers
        .filter()
        .meetingIdEqualTo(meetingId)
        .userIdEqualTo(userId)
        .findFirst();
  }

  static Future<void> createSpeakerMapping(
    int meetingId,
    int speakerId,
    int userId,
  ) async {
    await isar.writeTxn(() async {
      // 先检查是否已存在相同的 meetingId 和 speakerId 组合
      final existingSpeaker = await getSpeaker(meetingId, speakerId);

      if (existingSpeaker == null) {
        // 如果不存在，创建新的 Speaker 记录
        final newSpeaker = Speaker(
          meetingId: meetingId,
          speakerId: speakerId,
          userId: userId,
        );
        final id = await isar.speakers.put(newSpeaker);
        Log.log.info(
            'New speaker mapping created: id=$id, meetingId=$meetingId, speakerId=$speakerId, userId=$userId');
      } else {
        // 如果存在，只更新 userId
        final updatedSpeaker = Speaker(
          meetingId: existingSpeaker.meetingId,
          speakerId: existingSpeaker.speakerId,
          userId: userId,
          voiceFeature: existingSpeaker.voiceFeature,
        )..id = existingSpeaker.id; // 保持原有的自增ID

        final id = await isar.speakers.put(updatedSpeaker);
        Log.log.info(
            'Existing speaker mapping updated: id=$id, meetingId=$meetingId, speakerId=$speakerId, userId=$userId');
      }

      // 更新缓存
      final userName = await getUserName(userId);
      _speakerNameCache[(meetingId, speakerId)] = userName;
    });
  }

  // 获取指定时间后的发言记录
  static Future<List<Utterance>> getUtterancesAfter(
    int meetingId,
    int? lastAnalysisTime,
  ) async {
    if (lastAnalysisTime != null) {
      return await isar.utterances
          .where()
          .meetingIdEqualTo(meetingId)
          .filter()
          .startTimeGreaterThan(lastAnalysisTime) // 直接使用索引查询
          .sortByStartTime()
          .findAll();
    } else {
      return await isar.utterances
          .where()
          .meetingIdEqualTo(meetingId)
          .sortByStartTime()
          .findAll();
    }
  }

  // 获取会议的所有主张
  static Future<List<Proposition>> getMeetingPropositions(int meetingId) async {
    return await isar.propositions
        .where()
        .meetingIdEqualTo(meetingId)
        .findAll();
  }

  // 获取会议的所有主张立场
  static Future<List<PropositionStance>> getMeetingStances(
      int meetingId) async {
    return await isar.propositionStances
        .where()
        .meetingIdEqualTo(meetingId)
        .findAll();
  }

  // 获取用户名(优先从缓存获取)
  static Future<String> getUserName(int userId) async {
    if (_userNameCache.containsKey(userId)) {
      return _userNameCache[userId]!;
    }

    final user = await isar.users.get(userId);
    if (user != null) {
      _userNameCache[userId] = user.name;
      return user.name;
    }
    return 'Unknown User';
  }

  // 通过 speakerId 获取用户名
  static Future<String> getSpeakerName(int meetingId, int speakerId) async {
    final cacheKey = (meetingId, speakerId);
    if (_speakerNameCache.containsKey(cacheKey)) {
      return _speakerNameCache[cacheKey]!;
    }

    final speaker = await getSpeaker(meetingId, speakerId);
    if (speaker?.userId != null) {
      final name = await getUserName(speaker!.userId!);
      _speakerNameCache[cacheKey] = name;
      return name;
    }
    return 'Speaker $speakerId';
  }

  // 获取发言者名称(优先使用 userId)
  static Future<String> getUtteranceSpeakerName(Utterance utterance) async {
    if (utterance.userId != null) {
      return await getUserName(utterance.userId!);
    } else if (utterance.speakerId != null) {
      return await getSpeakerName(utterance.meetingId, utterance.speakerId!);
    }
    return 'Unknown Speaker';
  }

  // 清除缓存的方法(在需要时调用)
  static void clearCache() {
    _userNameCache.clear();
    _speakerNameCache.clear();
  }

  // 获取某个主张的所有立场
  static Future<List<PropositionStance>> getPropositionStancesByProposition(
    int propositionId,
  ) async {
    return await isar.propositionStances
        .filter()
        .propositionIdEqualTo(propositionId)
        .findAll();
  }

  // 获取所有会议列表
  static Future<List<Meeting>> getMeetings() async {
    return await isar.meetings.where().sortByCreatedAtDesc().findAll();
  }

  // 保存会议
  static Future<void> saveMeeting(Meeting meeting) async {
    await isar.writeTxn(() async {
      await isar.meetings.put(meeting);
    });
  }

  // 获取会议参与者
  static Future<List<MeetingParticipant>> getMeetingParticipants(
    int? meetingId,
  ) async {
    try {
      final query = isar.meetingParticipants.where();

      // 如果指定了会议ID，只获取该会议的参与者
      if (meetingId != null) {
        return await query.meetingIdEqualTo(meetingId).findAll();
      }

      // 否则获取所有参与者
      return await query.findAll();
    } catch (e) {
      Log.log.severe('Failed to get meeting participants: $e');
      return [];
    }
  }

  // 根据用户名查找用户
  static Future<User?> getUserByName(String userName) async {
    return await isar.users.where().nameEqualTo(userName).findFirst();
  }

  // 根据派别名查找派别
  static Future<Stance?> getStanceByName(
      String stanceName, int meetingId) async {
    return await isar.stances
        .filter()
        .meetingIdEqualTo(meetingId)
        .nameEqualTo(stanceName)
        .findFirst();
  }

  // 获取指定时间之后的对话记录（按时间排序，限制数量）
  static Future<List<Utterance>> getNewUtterances(
    int meetingId,
    int lastAnalysisTime, {
    int limit = 100,
  }) async {
    return await isar.utterances
        .filter()
        .meetingIdEqualTo(meetingId)
        .startTimeGreaterThan(lastAnalysisTime)
        .sortByStartTime()
        .limit(limit)
        .findAll();
  }

  // 获取会议的所有派别及其用户信息
  static Future<List<Map<String, dynamic>>> getStanceUsersInfo(
      int meetingId) async {
    try {
      // 获取会议的所有派别
      final stances = await getStancesByMeeting(meetingId);

      // 为每个派别获取用户信息
      return Future.wait(stances.map((stance) async {
        // 获取该派别的所有参与者
        final participants = await getMeetingParticipants(meetingId);
        final stanceParticipants =
            participants.where((p) => p.stanceId == stance.id);

        // 获取用户信息
        final users = await Future.wait(stanceParticipants.map((p) async {
          final user = await getUser(p.userId);
          return user?.name ?? "未知用户";
        }));

        return {
          "name": stance.name,
          "users": users,
        };
      }));
    } catch (e) {
      Log.log.severe('Failed to get stance users info: $e');
      return [];
    }
  }

  // 清除会议数据
  static Future<void> clearMeetingData(int meetingId) async {
    try {
      Log.log.info('Clearing data for meeting: $meetingId');
      await isar.writeTxn(() async {
        // 删除音频数据
        final audioDeleted = await isar.audioChunks
            .filter()
            .meetingIdEqualTo(meetingId)
            .deleteAll();

        // 删除对话记录
        final utteranceDeleted = await isar.utterances
            .filter()
            .meetingIdEqualTo(meetingId)
            .deleteAll();

        // 删除 speaker
        final speakerDeleted = await isar.speakers
            .filter()
            .meetingIdEqualTo(meetingId)
            .deleteAll();

        Log.log.info(
            'Deleted $audioDeleted audio chunks and $utteranceDeleted utterances and $speakerDeleted speakers');
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to clear meeting data: $e\n$stackTrace');
      rethrow;
    }
  }

  // 删除会议及其所有相关数据
  static Future<void> deleteMeeting(int meetingId) async {
    try {
      Log.log.info('Deleting meeting: $meetingId');
      await isar.writeTxn(() async {
        // 删除音频数据
        final audioDeleted = await isar.audioChunks
            .filter()
            .meetingIdEqualTo(meetingId)
            .deleteAll();

        // 删除对话记录
        final utteranceDeleted = await isar.utterances
            .filter()
            .meetingIdEqualTo(meetingId)
            .deleteAll();

        // 删除会议本身
        final meetingDeleted = await isar.meetings.delete(meetingId);

        Log.log.info(
            'Deleted meeting($meetingDeleted) with $audioDeleted audio chunks and $utteranceDeleted utterances');
      });
    } catch (e, stackTrace) {
      Log.log.severe('Failed to delete meeting: $e\n$stackTrace');
      rethrow;
    }
  }

  // 获取指定会议
  static Future<Meeting?> getMeetingById(int meetingId) async {
    return await isar.meetings.get(meetingId);
  }

  // 获取会议的所有对话记录（不分页）
  static Future<List<Utterance>> getAllUtterances(int meetingId) async {
    try {
      Log.log.info('Fetching all utterances for meeting $meetingId');
      final utterances =
          await isar.utterances.where().meetingIdEqualTo(meetingId).findAll();
      Log.log.info('Found ${utterances.length} utterances');
      return utterances;
    } catch (e) {
      Log.log.severe('Failed to get all utterances: $e');
      return [];
    }
  }

  // 获取会议的第一条发言记录（按时间排序）
  static Future<Utterance?> getFirstUtterance(int meetingId) async {
    return await isar.utterances
        .where()
        .meetingIdEqualTo(meetingId)
        .sortByStartTime()
        .findFirst();
  }

  // 获取会议的最后一条发言记录（按时间排序）
  static Future<Utterance?> getLastUtterance(int meetingId) async {
    return await isar.utterances
        .where()
        .meetingIdEqualTo(meetingId)
        .sortByEndTimeDesc()
        .findFirst();
  }
}
