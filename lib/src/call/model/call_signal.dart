/// Types of WebRTC signaling messages
enum SignalType {
  offer,
  answer,
  candidate,
  hangup,
  renegotiate,
}

extension SignalTypeX on SignalType {
  String toDbString() {
    switch (this) {
      case SignalType.offer:
        return 'offer';
      case SignalType.answer:
        return 'answer';
      case SignalType.candidate:
        return 'candidate';
      case SignalType.hangup:
        return 'hangup';
      case SignalType.renegotiate:
        return 'renegotiate';
    }
  }

  static SignalType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'offer':
        return SignalType.offer;
      case 'answer':
        return SignalType.answer;
      case 'candidate':
        return SignalType.candidate;
      case 'hangup':
        return SignalType.hangup;
      case 'renegotiate':
        return SignalType.renegotiate;
      default:
        throw ArgumentError('Unknown signal type: $type');
    }
  }
}

/// Represents a WebRTC signaling message
class CallSignal {
  final int? id;
  final String sessionId;
  final String senderId;
  final String receiverId;
  final SignalType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const CallSignal({
    this.id,
    required this.sessionId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  /// Create from Supabase row (rtc_signals table)
  factory CallSignal.fromJson(Map<String, dynamic> json) {
    return CallSignal(
      id: json['id'] as int?,
      sessionId: json['session_id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      type: SignalTypeX.fromString(json['signal_type'] as String),
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for database insert
  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'signal_type': type.toDbString(),
      'payload': payload,
    };
  }

  /// Check if this signal is for a specific user
  bool isForUser(String userId) => receiverId == userId;

  /// Check if this signal is from a specific user
  bool isFromUser(String userId) => senderId == userId;

  @override
  String toString() =>
      'CallSignal(type: $type, session: $sessionId, '
      'from: $senderId, to: $receiverId)';
}

/// SDP (Session Description Protocol) wrapper for offers and answers
class SdpMessage {
  final String sdp;
  final String type; // 'offer' or 'answer'

  const SdpMessage({required this.sdp, required this.type});

  factory SdpMessage.fromJson(Map<String, dynamic> json) {
    return SdpMessage(
      sdp: json['sdp'] as String,
      type: json['type'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'sdp': sdp, 'type': type};
}

/// ICE Candidate wrapper
class IceCandidate {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  const IceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  factory IceCandidate.fromJson(Map<String, dynamic> json) {
    return IceCandidate(
      candidate: json['candidate'] as String,
      sdpMid: json['sdpMid'] as String?,
      sdpMLineIndex: json['sdpMLineIndex'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      };
}
