/// Represents the state of a call throughout its lifecycle.
/// This is the single source of truth for call status.
enum CallStatus {
  /// No active call
  idle,
  
  /// Outgoing call - ringing at recipient's end
  calling,
  
  /// Incoming call - phone is ringing
  ringing,
  
  /// Call accepted, establishing WebRTC connection
  connecting,
  
  /// Call is active and media is flowing
  connected,
  
  /// Call is on hold
  onHold,
  
  /// Call is reconnecting after network issues
  reconnecting,
  
  /// Call ended normally
  ended,
  
  /// Call was declined by recipient
  declined,
  
  /// Call timed out (no answer)
  timeout,
  
  /// Call failed due to error
  failed,
  
  /// Incoming call was missed
  missed,
}

/// Extension to provide utility methods for CallStatus
extension CallStatusX on CallStatus {
  bool get isActive => this == CallStatus.connecting || 
                        this == CallStatus.connected || 
                        this == CallStatus.onHold ||
                        this == CallStatus.reconnecting;
  
  bool get isRinging => this == CallStatus.calling || this == CallStatus.ringing;
  
  bool get isEnded => this == CallStatus.ended || 
                       this == CallStatus.declined || 
                       this == CallStatus.timeout || 
                       this == CallStatus.failed ||
                       this == CallStatus.missed;
  
  String get displayName {
    switch (this) {
      case CallStatus.idle:
        return 'Idle';
      case CallStatus.calling:
        return 'Calling...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connecting:
        return 'Connecting...';
      case CallStatus.connected:
        return 'Connected';
      case CallStatus.onHold:
        return 'On Hold';
      case CallStatus.reconnecting:
        return 'Reconnecting...';
      case CallStatus.ended:
        return 'Call Ended';
      case CallStatus.declined:
        return 'Declined';
      case CallStatus.timeout:
        return 'No Answer';
      case CallStatus.failed:
        return 'Call Failed';
      case CallStatus.missed:
        return 'Missed Call';
    }
  }
  
  /// Convert from database status string
  static CallStatus fromDbStatus(String status) {
    switch (status.toLowerCase()) {
      case 'ringing':
        return CallStatus.ringing;
      case 'accepted':
        return CallStatus.connected;
      case 'rejected':
      case 'declined':
        return CallStatus.declined;
      case 'ended':
        return CallStatus.ended;
      case 'timeout':
        return CallStatus.timeout;
      case 'calling':
        return CallStatus.calling;
      case 'connecting':
        return CallStatus.connecting;
      default:
        return CallStatus.idle;
    }
  }
  
  /// Convert to database status string
  String toDbStatus() {
    switch (this) {
      case CallStatus.calling:
      case CallStatus.ringing:
        return 'ringing';
      case CallStatus.connecting:
      case CallStatus.connected:
      case CallStatus.onHold:
      case CallStatus.reconnecting:
        return 'accepted';
      case CallStatus.declined:
        return 'rejected';
      case CallStatus.ended:
        return 'ended';
      case CallStatus.timeout:
      case CallStatus.missed:
        return 'timeout';
      case CallStatus.idle:
      case CallStatus.failed:
        return 'ended';
    }
  }
}

/// Type of call
enum CallType {
  audio,
  video,
}

extension CallTypeX on CallType {
  String get displayName => this == CallType.video ? 'Video' : 'Voice';
  
  static CallType fromString(String type) {
    return type.toLowerCase() == 'video' ? CallType.video : CallType.audio;
  }
  
  String toDbString() => this == CallType.video ? 'video' : 'audio';
}
