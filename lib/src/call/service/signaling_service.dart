import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../model/call_state.dart';
import '../../storage/signed_url_helper.dart';

/// Represents a WebRTC signal from the database
class WebRTCSignal {
  final int id;
  final String callId;
  final String senderId;
  final String signalType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  WebRTCSignal({
    required this.id,
    required this.callId,
    required this.senderId,
    required this.signalType,
    required this.payload,
    required this.createdAt,
  });

  factory WebRTCSignal.fromJson(Map<String, dynamic> json) {
    return WebRTCSignal(
      id: json['id'] as int,
      callId: json['call_id'] as String,
      senderId: json['sender_id'] as String,
      signalType: json['signal_type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Represents an active call from the database
class ActiveCall {
  final String id;
  final String? chatId;
  final String callerId;
  final String calleeId;
  final String callType; // 'audio' or 'video'
  final String status; // 'calling', 'ringing', 'connecting', 'active', 'ended', 'declined', 'failed'
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final DateTime createdAt;
  
  // Profile data
  final String? callerName;
  final String? callerAvatar;
  final String? calleeName;
  final String? calleeAvatar;

  /// Calculate call duration from database timestamps (single source of truth)
  int get durationSeconds {
    if (answeredAt == null) return 0;
    final end = endedAt ?? DateTime.now();
    return end.difference(answeredAt!).inSeconds;
  }

  /// Whether this call was answered/connected
  bool get wasConnected => answeredAt != null;

  ActiveCall({
    required this.id,
    this.chatId,
    required this.callerId,
    required this.calleeId,
    required this.callType,
    required this.status,
    this.answeredAt,
    this.endedAt,
    required this.createdAt,
    this.callerName,
    this.callerAvatar,
    this.calleeName,
    this.calleeAvatar,
  });

  factory ActiveCall.fromJson(Map<String, dynamic> json) {
    return ActiveCall(
      id: json['id'] as String,
      chatId: json['chat_id'] as String?,
      callerId: json['caller_id'] as String,
      calleeId: json['callee_id'] as String,
      callType: json['call_type'] as String? ?? 'audio',
      status: json['status'] as String? ?? 'calling',
      answeredAt: json['answered_at'] != null 
          ? DateTime.parse(json['answered_at'] as String) 
          : null,
      endedAt: json['ended_at'] != null 
          ? DateTime.parse(json['ended_at'] as String) 
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      callerName: json['caller']?['full_name'] as String? ?? 
                  json['caller']?['username'] as String?,
      callerAvatar: json['caller']?['avatar_url'] as String?,
      calleeName: json['callee']?['full_name'] as String? ?? 
                  json['callee']?['username'] as String?,
      calleeAvatar: json['callee']?['avatar_url'] as String?,
    );
  }

  bool isCaller(String userId) => callerId == userId;
  
  String remoteUserId(String currentUserId) =>
      isCaller(currentUserId) ? calleeId : callerId;
      
  String? remoteUserName(String currentUserId) =>
      isCaller(currentUserId) ? calleeName : callerName;
      
  String? remoteUserAvatar(String currentUserId) =>
      isCaller(currentUserId) ? calleeAvatar : callerAvatar;

  ActiveCall copyWith({
    String? id,
    String? chatId,
    String? callerId,
    String? calleeId,
    String? callType,
    String? status,
    DateTime? answeredAt,
    DateTime? endedAt,
    DateTime? createdAt,
    String? callerName,
    String? callerAvatar,
    String? calleeName,
    String? calleeAvatar,
  }) {
    return ActiveCall(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      createdAt: createdAt ?? this.createdAt,
      callerName: callerName ?? this.callerName,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      calleeName: calleeName ?? this.calleeName,
      calleeAvatar: calleeAvatar ?? this.calleeAvatar,
    );
  }
}

/// Service for handling WebRTC signaling via Supabase Realtime.
/// Uses 'active_calls' for call state and 'webrtc_signals' for signaling.
class SignalingService {
  final SupabaseClient _client;
  
  RealtimeChannel? _signalChannel;
  RealtimeChannel? _callChannel;
  
  final _signalController = StreamController<WebRTCSignal>.broadcast();
  final _callUpdateController = StreamController<ActiveCall>.broadcast();
  
  String? _currentUserId;

  SignalingService(this._client);

  /// Stream of incoming signaling messages
  Stream<WebRTCSignal> get signals => _signalController.stream;
  
  /// Stream of call status updates
  Stream<ActiveCall> get callUpdates => _callUpdateController.stream;

  /// Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Initialize signaling for a call
  Future<void> initialize(String callId) async {
    _currentUserId = currentUserId;
    
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }

    await _subscribeToSignals(callId);
    await _subscribeToCallUpdates(callId);
  }

  /// Subscribe to WebRTC signals for the call
  Future<void> _subscribeToSignals(String callId) async {
    await _signalChannel?.unsubscribe();
    
    _signalChannel = _client
        .channel('webrtc_signals:$callId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'webrtc_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: callId,
          ),
          callback: (payload) {
            try {
              final signal = WebRTCSignal.fromJson(payload.newRecord);
              // Only process signals not from ourselves
              if (signal.senderId != _currentUserId) {
                debugPrint('SignalingService: Received ${signal.signalType} from ${signal.senderId}');
                _signalController.add(signal);
              }
            } catch (e) {
              debugPrint('SignalingService: Error parsing signal: $e');
            }
          },
        )
        .subscribe();
  }

  /// Subscribe to call status updates
  Future<void> _subscribeToCallUpdates(String callId) async {
    await _callChannel?.unsubscribe();
    
    _callChannel = _client
        .channel('active_call:$callId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'active_calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: callId,
          ),
          callback: (payload) async {
            try {
              // Realtime doesn't include joined data, so re-fetch the full call
              final callId = payload.newRecord['id'] as String?;
              if (callId != null) {
                final fullCall = await getCall(callId);
                if (fullCall != null) {
                  debugPrint('SignalingService: Call update - ${fullCall.status}');
                  _callUpdateController.add(fullCall);
                }
              }
            } catch (e) {
              debugPrint('SignalingService: Error parsing call update: $e');
            }
          },
        )
        .subscribe();
  }

  /// Create a new active call
  Future<ActiveCall> createCall({
    required String calleeId,
    required CallType type,
    String? chatId,
  }) async {
    final callerId = currentUserId;
    if (callerId == null) throw Exception('User not authenticated');

    // Insert into active_calls table
    final response = await _client
        .from('active_calls')
        .insert({
          'caller_id': callerId,
          'callee_id': calleeId,
          'call_type': type.toDbString(),
          'status': 'calling',
          'chat_id': chatId,
        })
        .select('''
          *,
          caller:profiles!active_calls_caller_id_fkey(id, full_name, username, avatar_url),
          callee:profiles!active_calls_callee_id_fkey(id, full_name, username, avatar_url)
        ''')
        .single();

    return _signAvatarUrls(ActiveCall.fromJson(response));
  }

  /// Sign avatar URLs in an ActiveCall
  Future<ActiveCall> _signAvatarUrls(ActiveCall call) async {
    String? callerAvatar = call.callerAvatar;
    String? calleeAvatar = call.calleeAvatar;
    
    if (callerAvatar != null && callerAvatar.isNotEmpty && !callerAvatar.startsWith('http')) {
      callerAvatar = await SignedUrlHelper.getAvatarUrl(_client, callerAvatar);
    }
    if (calleeAvatar != null && calleeAvatar.isNotEmpty && !calleeAvatar.startsWith('http')) {
      calleeAvatar = await SignedUrlHelper.getAvatarUrl(_client, calleeAvatar);
    }
    
    return call.copyWith(
      callerAvatar: callerAvatar,
      calleeAvatar: calleeAvatar,
    );
  }

  /// Get an existing active call
  Future<ActiveCall?> getCall(String callId) async {
    try {
      final response = await _client
          .from('active_calls')
          .select('''
            *,
            caller:profiles!active_calls_caller_id_fkey(id, full_name, username, avatar_url),
            callee:profiles!active_calls_callee_id_fkey(id, full_name, username, avatar_url)
          ''')
          .eq('id', callId)
          .maybeSingle();

      if (response == null) return null;
      return _signAvatarUrls(ActiveCall.fromJson(response));
    } catch (e) {
      debugPrint('SignalingService: Error getting call: $e');
      return null;
    }
  }

  /// Update call status
  Future<void> updateCallStatus(String callId, String status) async {
    final updates = <String, dynamic>{
      'status': status,
    };

    if (status == 'active') {
      updates['answered_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (status == 'ended' || status == 'declined' || status == 'failed') {
      updates['ended_at'] = DateTime.now().toUtc().toIso8601String();
    }

    await _client
        .from('active_calls')
        .update(updates)
        .eq('id', callId);
  }

  /// Save call to history when it ends
  Future<void> saveCallToHistory(ActiveCall call) async {
    try {
      int? durationSeconds;
      if (call.answeredAt != null) {
        final endTime = call.endedAt ?? DateTime.now();
        durationSeconds = endTime.difference(call.answeredAt!).inSeconds;
      }

      // Map active_calls status to calls table status
      String historyStatus;
      switch (call.status) {
        case 'active':
        case 'ended':
          historyStatus = call.answeredAt != null ? 'accepted' : 'ended';
          break;
        case 'declined':
          historyStatus = 'declined';
          break;
        case 'failed':
          historyStatus = 'missed';
          break;
        default:
          historyStatus = 'missed';
      }

      await _client.from('calls').insert({
        'chat_id': call.chatId,
        'caller_id': call.callerId,
        'callee_id': call.calleeId,
        'type': call.callType,
        'status': historyStatus,
        'started_at': call.createdAt.toUtc().toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
      });
      debugPrint('SignalingService: Call saved to history');
    } catch (e) {
      debugPrint('SignalingService: Error saving call to history: $e');
    }
  }

  /// Send an SDP offer
  Future<void> sendOffer({
    required String callId,
    required String sdp,
  }) async {
    await _sendSignal(
      callId: callId,
      signalType: 'offer',
      payload: {'sdp': sdp, 'type': 'offer'},
    );
  }

  /// Send an SDP answer
  Future<void> sendAnswer({
    required String callId,
    required String sdp,
  }) async {
    await _sendSignal(
      callId: callId,
      signalType: 'answer',
      payload: {'sdp': sdp, 'type': 'answer'},
    );
  }

  /// Send an ICE candidate
  Future<void> sendIceCandidate({
    required String callId,
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {
    await _sendSignal(
      callId: callId,
      signalType: 'ice_candidate',
      payload: {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      },
    );
  }

  /// Send call accepted signal
  Future<void> sendCallAccepted(String callId) async {
    await _sendSignal(
      callId: callId,
      signalType: 'call_accepted',
      payload: {},
    );
  }

  /// Send call declined signal
  Future<void> sendCallDeclined(String callId) async {
    await _sendSignal(
      callId: callId,
      signalType: 'call_declined',
      payload: {},
    );
  }

  /// Send call ended signal
  Future<void> sendCallEnded(String callId) async {
    await _sendSignal(
      callId: callId,
      signalType: 'call_ended',
      payload: {'reason': 'user_hangup'},
    );
  }

  /// Send a generic signal (for reconnection, etc.)
  Future<void> sendSignal({
    required String callId,
    required String signalType,
    required Map<String, dynamic> payload,
  }) async {
    await _sendSignal(
      callId: callId,
      signalType: signalType,
      payload: payload,
    );
  }

  /// Internal method to send a signal
  Future<void> _sendSignal({
    required String callId,
    required String signalType,
    required Map<String, dynamic> payload,
  }) async {
    final senderId = currentUserId;
    if (senderId == null) throw Exception('User not authenticated');

    debugPrint('SignalingService: Sending $signalType');

    await _client.from('webrtc_signals').insert({
      'call_id': callId,
      'sender_id': senderId,
      'signal_type': signalType,
      'payload': payload,
    });
  }

  /// Fetch pending signals (for when joining mid-call)
  Future<List<WebRTCSignal>> fetchPendingSignals(String callId) async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      final response = await _client
          .from('webrtc_signals')
          .select()
          .eq('call_id', callId)
          .neq('sender_id', userId) // Get signals not from ourselves
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => WebRTCSignal.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('SignalingService: Error fetching pending signals: $e');
      return [];
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    await _signalChannel?.unsubscribe();
    await _callChannel?.unsubscribe();
    _signalChannel = null;
    _callChannel = null;
    await _signalController.close();
    await _callUpdateController.close();
  }

  /// Clean up for a specific call without closing streams
  Future<void> leaveCall() async {
    await _signalChannel?.unsubscribe();
    await _callChannel?.unsubscribe();
    _signalChannel = null;
    _callChannel = null;
  }
}
