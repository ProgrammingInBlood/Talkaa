import 'call_state.dart';

/// Represents a call session with all relevant metadata.
/// This is the single source of truth for call information.
class CallSession {
  final String id;
  final String? chatId;
  final String callerId;
  final String calleeId;
  final CallType type;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  
  // Metadata populated from profiles
  final String? callerName;
  final String? callerAvatar;
  final String? calleeName;
  final String? calleeAvatar;

  const CallSession({
    required this.id,
    this.chatId,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.callerName,
    this.callerAvatar,
    this.calleeName,
    this.calleeAvatar,
  });

  /// Duration of the call in seconds (only valid after call ends)
  int? get durationSeconds {
    if (acceptedAt == null) return null;
    final end = endedAt ?? DateTime.now();
    return end.difference(acceptedAt!).inSeconds;
  }

  /// Formatted duration string (MM:SS or HH:MM:SS)
  String get durationString {
    final seconds = durationSeconds ?? 0;
    if (seconds == 0 && acceptedAt == null) return '--:--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Check if current user is the caller
  bool isCaller(String currentUserId) => callerId == currentUserId;

  /// Get the remote user's ID (the other party in the call)
  String remoteUserId(String currentUserId) =>
      isCaller(currentUserId) ? calleeId : callerId;

  /// Get the remote user's name
  String? remoteUserName(String currentUserId) =>
      isCaller(currentUserId) ? calleeName : callerName;

  /// Get the remote user's avatar
  String? remoteUserAvatar(String currentUserId) =>
      isCaller(currentUserId) ? calleeAvatar : callerAvatar;

  /// Create from Supabase row
  factory CallSession.fromJson(Map<String, dynamic> json) {
    return CallSession(
      id: json['id'] as String,
      chatId: json['chat_id'] as String?,
      callerId: json['caller_id'] as String,
      calleeId: json['callee_id'] as String,
      type: CallTypeX.fromString(json['type'] as String? ?? 'audio'),
      status: CallStatusX.fromDbStatus(json['status'] as String? ?? 'ringing'),
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null 
          ? DateTime.parse(json['accepted_at'] as String) 
          : null,
      endedAt: json['ended_at'] != null 
          ? DateTime.parse(json['ended_at'] as String) 
          : null,
      callerName: json['caller']?['full_name'] as String? ?? 
                  json['caller']?['username'] as String?,
      callerAvatar: json['caller']?['avatar_url'] as String?,
      calleeName: json['callee']?['full_name'] as String? ?? 
                  json['callee']?['username'] as String?,
      calleeAvatar: json['callee']?['avatar_url'] as String?,
    );
  }

  /// Convert to JSON for database operations
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'caller_id': callerId,
      'callee_id': calleeId,
      'type': type.toDbString(),
      'status': status.toDbStatus(),
      'created_at': createdAt.toUtc().toIso8601String(),
      if (acceptedAt != null) 
        'accepted_at': acceptedAt!.toUtc().toIso8601String(),
      if (endedAt != null) 
        'ended_at': endedAt!.toUtc().toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  CallSession copyWith({
    String? id,
    String? chatId,
    String? callerId,
    String? calleeId,
    CallType? type,
    CallStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? endedAt,
    String? callerName,
    String? callerAvatar,
    String? calleeName,
    String? calleeAvatar,
  }) {
    return CallSession(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      endedAt: endedAt ?? this.endedAt,
      callerName: callerName ?? this.callerName,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      calleeName: calleeName ?? this.calleeName,
      calleeAvatar: calleeAvatar ?? this.calleeAvatar,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallSession &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status;

  @override
  int get hashCode => id.hashCode ^ status.hashCode;

  @override
  String toString() =>
      'CallSession(id: $id, status: $status, type: $type, '
      'caller: $callerId, callee: $calleeId)';
}
