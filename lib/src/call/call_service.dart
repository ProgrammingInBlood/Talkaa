import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import '../notify/call_notifications.dart';
import 'model/call_state.dart';
import 'service/signaling_service.dart';
import 'service/webrtc_service.dart';

/// The main call controller - single source of truth for all call state.
/// This orchestrates SignalingService and WebRTCService.
/// Uses 'active_calls' table for call management and 'webrtc_signals' for signaling.
class CallController extends ChangeNotifier {
  final SupabaseClient _client;
  final SignalingService _signalingService;
  final WebRTCService _webrtcService;
  
  ActiveCall? _currentCall;
  CallStatus _status = CallStatus.idle;
  Timer? _durationTimer;
  DateTime? _connectedAt; // Server-synced connection time
  String? _error;
  
  StreamSubscription? _signalSubscription;
  StreamSubscription? _callUpdateSubscription;
  StreamSubscription? _iceCandidateSubscription;
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _notificationActionSubscription;
  StreamSubscription? _networkRestoredSubscription;
  StreamSubscription? _renegotiationSubscription;
  StreamSubscription? _iceConnectionStateSubscription;
  Timer? _signalPollingTimer; // Backup polling for signals

  // Queued ICE candidates (received before remote description is set)
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  CallController(this._client)
      : _signalingService = SignalingService(_client),
        _webrtcService = WebRTCService() {
    _listenToNotificationActions();
  }

  // === Getters ===
  
  ActiveCall? get currentCall => _currentCall;
  CallStatus get status => _status;
  /// Call duration calculated from server timestamp (single source of truth)
  int get callDurationSeconds {
    if (_connectedAt == null) return 0;
    return DateTime.now().difference(_connectedAt!).inSeconds;
  }
  String? get error => _error;
  bool get hasActiveCall => _status.isActive || _status.isRinging;
  
  String? get currentUserId => _client.auth.currentUser?.id;
  
  // WebRTC state
  bool get isMuted => _webrtcService.isMuted;
  bool get isVideoEnabled => _webrtcService.isVideoEnabled;
  bool get isSpeakerOn => _webrtcService.isSpeakerOn;
  bool get isFrontCamera => _webrtcService.isFrontCamera;
  CallType get callType => _currentCall != null 
      ? CallTypeX.fromString(_currentCall!.callType) 
      : CallType.audio;
  
  // Media streams
  Stream<MediaStream?> get localStream => _webrtcService.localStream;
  Stream<MediaStream?> get remoteStream => _webrtcService.remoteStream;
  MediaStream? get currentLocalStream => _webrtcService.currentLocalStream;
  MediaStream? get currentRemoteStream => _webrtcService.currentRemoteStream;

  /// Duration formatted as MM:SS or HH:MM:SS
  String get durationString {
    final seconds = callDurationSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // === Call Actions ===

  /// Start an outgoing call
  Future<void> startCall({
    required String calleeId,
    required CallType type,
    String? chatId,
    String? calleeName,
    String? calleeAvatar,
  }) async {
    if (_status != CallStatus.idle) {
      debugPrint('CallController: Cannot start call - already in a call');
      return;
    }

    try {
      _updateStatus(CallStatus.calling);
      _error = null;

      // We are the initiator (caller) - important for reconnection coordination
      _isInitiator = true;
      
      // Create call in active_calls table
      _currentCall = await _signalingService.createCall(
        calleeId: calleeId,
        type: type,
        chatId: chatId,
      );

      debugPrint('CallController: Created call ${_currentCall!.id}');

      // Initialize signaling and WebRTC
      await _signalingService.initialize(_currentCall!.id);
      await _webrtcService.initialize(type);

      // Subscribe to events
      _subscribeToSignals();
      _subscribeToCallUpdates();
      _subscribeToIceCandidates();
      _subscribeToConnectionState();
      _subscribeToNetworkRestored();
      _subscribeToIceConnectionState();

      // Create and send offer
      final offer = await _webrtcService.createOffer();
      await _signalingService.sendOffer(
        callId: _currentCall!.id,
        sdp: offer.sdp!,
      );

      // Show outgoing call notification
      await CallNotifications.startForegroundService(
        callerName: calleeName ?? _currentCall!.calleeName ?? 'Calling...',
        callId: _currentCall!.id,
        avatarUrl: calleeAvatar ?? _currentCall!.calleeAvatar,
        style: 'outgoing',
      );

      // Send push notification to callee
      final callerName = await _getCurrentUserName();
      final callerAvatar = await _getCurrentUserAvatar();
      await _sendCallInvitePush(
        calleeId: calleeId,
        callerName: callerName,
        callId: _currentCall!.id,
        callType: type,
        callerAvatar: callerAvatar,
      );

      // Start polling for signals as backup (in case realtime fails)
      _startSignalPolling();

      notifyListeners();
    } catch (e) {
      debugPrint('CallController: Error starting call: $e');
      _error = e.toString();
      await endCall(reason: 'error');
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall() async {
    if (_currentCall == null || _status != CallStatus.ringing) {
      debugPrint('CallController: Cannot accept - no incoming call');
      return;
    }

    try {
      _updateStatus(CallStatus.connecting);

      // Initialize WebRTC
      final type = CallTypeX.fromString(_currentCall!.callType);
      await _webrtcService.initialize(type);

      // Subscribe to ICE candidates
      _subscribeToIceCandidates();
      _subscribeToConnectionState();
      _subscribeToNetworkRestored();
      _subscribeToIceConnectionState();

      // Fetch and process pending signals (offer should be there)
      final pendingSignals = await _signalingService.fetchPendingSignals(
        _currentCall!.id,
      );

      for (final signal in pendingSignals) {
        await _handleSignal(signal);
      }

      // Update call status to active
      await _signalingService.updateCallStatus(_currentCall!.id, 'active');
      
      // Send call accepted signal
      await _signalingService.sendCallAccepted(_currentCall!.id);

      // Transition directly to connected - don't rely on WebRTC callbacks
      // as they don't fire reliably on Android
      _updateStatus(CallStatus.connected);
      debugPrint('CallController: Call accepted, now connected');

      // Update notification to ongoing
      final userId = currentUserId;
      if (userId != null) {
        final remoteName = _currentCall!.remoteUserName(userId) ?? 'On Call';
        await CallNotifications.startForegroundService(
          callerName: remoteName,
          callId: _currentCall!.id,
          avatarUrl: _currentCall!.remoteUserAvatar(userId),
          style: 'ongoing',
        );
      }

      // Send accept notification to caller
      await _sendCallAcceptPush();

      notifyListeners();
    } catch (e) {
      debugPrint('CallController: Error accepting call: $e');
      _error = e.toString();
      await endCall(reason: 'error');
    }
  }

  /// Decline an incoming call
  Future<void> declineCall() async {
    if (_currentCall == null) return;

    // Mark as intentional disconnect
    _intentionalDisconnect = true;
    
    try {
      // Update call status
      await _signalingService.updateCallStatus(_currentCall!.id, 'declined');
      
      // Send declined signal
      await _signalingService.sendCallDeclined(_currentCall!.id);

      // Send decline push notification
      await _sendCallDeclinePush();

      // Save to call history
      final updatedCall = await _signalingService.getCall(_currentCall!.id);
      if (updatedCall != null) {
        await _signalingService.saveCallToHistory(updatedCall);
      }

      await _cleanup(CallStatus.declined);
    } catch (e) {
      debugPrint('CallController: Error declining call: $e');
      await _cleanup(CallStatus.failed);
    }
  }

  /// End the current call
  Future<void> endCall({String reason = 'user_hangup'}) async {
    // Mark as intentional disconnect to prevent reconnection attempts
    _intentionalDisconnect = true;
    
    if (_currentCall == null) {
      await _cleanup(CallStatus.idle);
      return;
    }

    try {
      // Send call ended signal
      await _signalingService.sendCallEnded(_currentCall!.id);

      // Update call status
      await _signalingService.updateCallStatus(_currentCall!.id, 'ended');

      // Send end push notification
      await _sendCallEndPush();

      // Save to call history
      final updatedCall = await _signalingService.getCall(_currentCall!.id);
      if (updatedCall != null) {
        await _signalingService.saveCallToHistory(updatedCall);
      }

      await _cleanup(CallStatus.ended);
    } catch (e) {
      debugPrint('CallController: Error ending call: $e');
      await _cleanup(CallStatus.ended);
    }
  }

  /// Handle incoming call (from push notification)
  Future<void> handleIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    CallType? callType,
  }) async {
    if (_status != CallStatus.idle) {
      debugPrint('CallController: Rejecting incoming call - already busy');
      // TODO: Send busy signal
      return;
    }

    try {
      // Fetch call details from active_calls
      _currentCall = await _signalingService.getCall(callId);
      if (_currentCall == null) {
        debugPrint('CallController: Call not found');
        return;
      }

      _updateStatus(CallStatus.ringing);

      // Update call status to ringing
      await _signalingService.updateCallStatus(callId, 'ringing');

      // Initialize signaling
      await _signalingService.initialize(callId);
      _subscribeToSignals();
      _subscribeToCallUpdates();

      // Show incoming call notification
      await CallNotifications.startForegroundService(
        callerName: callerName,
        callId: callId,
        avatarUrl: callerAvatar,
        style: 'incoming',
      );

      notifyListeners();
    } catch (e) {
      debugPrint('CallController: Error handling incoming call: $e');
      _error = e.toString();
      await _cleanup(CallStatus.failed);
    }
  }

  // === Media Controls ===

  Future<void> toggleMute() async {
    await _webrtcService.toggleMute();
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    await _webrtcService.toggleVideo();
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    await _webrtcService.toggleSpeaker();
    notifyListeners();
  }

  Future<void> setSpeakerOn(bool enabled) async {
    await _webrtcService.setSpeakerOn(enabled);
    notifyListeners();
  }

  Future<List<Map<String, String>>> getAudioOutputDevices() async {
    // Return standard audio output options for mobile
    return [
      {'id': 'earpiece', 'label': 'Phone Earpiece', 'icon': 'hearing'},
      {'id': 'speaker', 'label': 'Speaker', 'icon': 'volume_up'},
      {'id': 'bluetooth', 'label': 'Bluetooth', 'icon': 'bluetooth_audio'},
    ];
  }

  Future<List<Map<String, String>>> getAudioInputDevices() async {
    // Return standard audio input options for mobile
    return [
      {'id': 'default', 'label': 'Phone Microphone', 'icon': 'mic'},
      {'id': 'bluetooth', 'label': 'Bluetooth Mic', 'icon': 'bluetooth_audio'},
    ];
  }

  Future<void> selectAudioOutput(String deviceId) async {
    await _webrtcService.selectAudioOutput(deviceId);
    notifyListeners();
  }

  Future<void> selectAudioInput(String deviceId) async {
    await _webrtcService.selectAudioInput(deviceId);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _webrtcService.switchCamera();
    notifyListeners();
  }

  Future<void> enableVideo() async {
    await _webrtcService.enableVideo();
    notifyListeners();
  }

  // === Private Methods ===

  void _updateStatus(CallStatus newStatus) {
    if (_status == newStatus) return;
    
    debugPrint('CallController: Status changed: $_status -> $newStatus');
    _status = newStatus;

    // Start duration timer when connected
    if (newStatus == CallStatus.connected) {
      // Start timer and update notification (async, but don't await to avoid blocking)
      _onCallConnected();
    } else if (newStatus.isEnded) {
      _stopDurationTimer();
    }

    notifyListeners();
  }
  
  /// Called when WebRTC connection is established
  Future<void> _onCallConnected() async {
    await _startDurationTimer();
    await _updateNotificationToOngoing();
  }
  
  Future<void> _updateNotificationToOngoing() async {
    if (_currentCall == null || currentUserId == null) return;
    
    final remoteName = _currentCall!.remoteUserName(currentUserId!) ?? 'On Call';
    await CallNotifications.startForegroundService(
      callerName: remoteName,
      callId: _currentCall!.id,
      avatarUrl: _currentCall!.remoteUserAvatar(currentUserId!),
      style: 'ongoing',
    );
  }

  Future<void> _startDurationTimer() async {
    // Refresh call data to get the server-set answered_at timestamp
    if (_currentCall != null) {
      final refreshedCall = await _signalingService.getCall(_currentCall!.id);
      if (refreshedCall != null) {
        _currentCall = refreshedCall;
      }
    }
    
    // Use server timestamp as source of truth if available
    _connectedAt = _currentCall?.answeredAt ?? DateTime.now();
    debugPrint('CallController: Timer started, connectedAt=$_connectedAt');
    
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _subscribeToSignals() {
    _signalSubscription?.cancel();
    _signalSubscription = _signalingService.signals.listen(_handleSignal);
  }

  void _subscribeToCallUpdates() {
    _callUpdateSubscription?.cancel();
    _callUpdateSubscription = _signalingService.callUpdates.listen((call) {
      _currentCall = call;
      
      // Map active_calls status to CallStatus
      if (call.status == 'ended' || call.status == 'declined' || call.status == 'failed') {
        final callStatus = call.status == 'declined' 
            ? CallStatus.declined 
            : CallStatus.ended;
        if (_status != callStatus) {
          _updateStatus(callStatus);
          _cleanup(callStatus);
        }
      }
      
      notifyListeners();
    });
  }

  void _subscribeToIceCandidates() {
    _iceCandidateSubscription?.cancel();
    _iceCandidateSubscription = _webrtcService.iceCandidates.listen((candidate) async {
      if (_currentCall == null) return;
      
      await _signalingService.sendIceCandidate(
        callId: _currentCall!.id,
        candidate: candidate.candidate!,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
      );
    });
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;
  Timer? _reconnectTimeoutTimer;
  Timer? _disconnectDelayTimer;
  bool _isInitiator = false; // Track if we initiated the call (for reconnection coordination)
  bool _intentionalDisconnect = false; // Flag to track if we're intentionally ending

  void _subscribeToConnectionState() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _webrtcService.connectionState.listen((state) {
      debugPrint('CallController: Connection state changed: $state (status: $_status, reconnecting: ${_webrtcService.isReconnecting}, intentional: $_intentionalDisconnect)');
      
      // Ignore state changes if we're intentionally disconnecting
      if (_intentionalDisconnect) {
        debugPrint('CallController: Ignoring state change - intentional disconnect');
        return;
      }
      
      // Ignore state changes during active reconnection (peer connection being recreated)
      if (_webrtcService.isReconnecting && state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        debugPrint('CallController: Ignoring Closed state - reconnection in progress');
        return;
      }
      
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _onConnectionRestored();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Start reconnection after a short delay to allow natural recovery
          _scheduleReconnectionCheck();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          // Connection truly failed, attempt full reconnection immediately
          _handleConnectionFailed();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          // Only cleanup if not reconnecting and call is still active
          if (_status.isActive && _status != CallStatus.reconnecting) {
            debugPrint('CallController: Connection closed unexpectedly, attempting reconnection');
            _handleConnectionFailed();
          }
          break;
        default:
          break;
      }
    });
  }
  
  /// Schedule a reconnection check after a delay to allow natural recovery
  void _scheduleReconnectionCheck() {
    if (_status != CallStatus.connected && _status != CallStatus.reconnecting) return;
    
    _disconnectDelayTimer?.cancel();
    _disconnectDelayTimer = Timer(const Duration(seconds: 2), () {
      // If still disconnected after delay, start reconnection
      if (_status == CallStatus.connected || _status == CallStatus.reconnecting) {
        debugPrint('CallController: Still disconnected after delay, starting reconnection');
        _handleConnectionFailed();
      }
    });
  }

  /// Subscribe to network restoration events
  void _subscribeToNetworkRestored() {
    _networkRestoredSubscription?.cancel();
    _networkRestoredSubscription = _webrtcService.networkRestored.listen((_) {
      debugPrint('CallController: Network restored detected');
      if (_status == CallStatus.reconnecting || 
          (_status.isActive && _webrtcService.isReconnecting)) {
        debugPrint('CallController: Triggering full reconnection after network restore');
        _performFullReconnection();
      }
    });
  }

  /// Subscribe to ICE connection state for more reliable disconnect detection on mobile
  void _subscribeToIceConnectionState() {
    _iceConnectionStateSubscription?.cancel();
    _iceConnectionStateSubscription = _webrtcService.iceConnectionState.listen((state) {
      debugPrint('CallController: ICE state: $state (status: $_status, intentional: $_intentionalDisconnect)');
      
      if (_intentionalDisconnect) return;
      
      // ICE state is more reliable on mobile for detecting network issues
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          if (_status == CallStatus.connected) {
            debugPrint('CallController: ICE disconnected - scheduling reconnection check');
            _scheduleReconnectionCheck();
          }
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          if (_status == CallStatus.connected || _status == CallStatus.reconnecting) {
            debugPrint('CallController: ICE failed - triggering reconnection');
            _handleConnectionFailed();
          }
          break;
        default:
          break;
      }
    });
  }

  void _onConnectionRestored() {
    debugPrint('CallController: Connection restored');
    _reconnectTimer?.cancel();
    _reconnectTimeoutTimer?.cancel();
    _reconnectAttempts = 0;
    _webrtcService.reconnectionComplete();
    
    if (_status == CallStatus.reconnecting) {
      _updateStatus(CallStatus.connected);
      notifyListeners();
    } else if (_status != CallStatus.connected) {
      _updateStatus(CallStatus.connected);
    }
  }

  void _handleConnectionFailed() {
    debugPrint('CallController: Connection failed, attempting full reconnection');
    _updateStatus(CallStatus.reconnecting);
    notifyListeners();
    
    // On mobile, ICE restart often doesn't work - do full reconnection immediately
    _performFullReconnection();
  }

  /// Perform a FULL peer connection teardown and rebuild
  /// This is the most reliable way to reconnect on mobile
  Future<void> _performFullReconnection() async {
    if (_currentCall == null || _status == CallStatus.idle) return;
    
    // Only the original caller initiates reconnection to avoid conflicts
    if (!_isInitiator) {
      debugPrint('CallController: Waiting for caller to initiate reconnection');
      _startReconnectTimeout();
      return;
    }
    
    // Check max attempts BEFORE incrementing
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('CallController: Max reconnect attempts reached ($_reconnectAttempts/$_maxReconnectAttempts)');
      _updateStatus(CallStatus.failed);
      await endCall(reason: 'reconnect_failed');
      return;
    }
    
    _reconnectAttempts++;
    debugPrint('CallController: Full reconnection attempt $_reconnectAttempts/$_maxReconnectAttempts');
    
    // Start timeout for this reconnection attempt
    _startReconnectTimeout();
    
    try {
      // Reset remote description flag - we need new offer/answer exchange
      _remoteDescriptionSet = false;
      _pendingIceCandidates.clear();
      
      // ALWAYS do full peer connection recreation on mobile
      // ICE restart alone is unreliable
      debugPrint('CallController: Recreating peer connection...');
      final offer = await _webrtcService.recreatePeerConnection();
      
      if (offer == null) {
        debugPrint('CallController: Failed to create reconnection offer');
        _scheduleRetry();
        return;
      }
      
      // Send the new offer
      await _signalingService.sendOffer(
        callId: _currentCall!.id,
        sdp: offer.sdp!,
      );
      
      debugPrint('CallController: Reconnection offer sent, waiting for answer...');
    } catch (e) {
      debugPrint('CallController: Error during reconnect: $e');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_status == CallStatus.reconnecting) {
        _performFullReconnection();
      }
    });
  }

  void _startReconnectTimeout() {
    _reconnectTimeoutTimer?.cancel();
    _reconnectTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (_status == CallStatus.reconnecting) {
        if (_isInitiator && _reconnectAttempts < _maxReconnectAttempts) {
          debugPrint('CallController: Reconnection timeout, trying again');
          _performFullReconnection();
        } else if (!_isInitiator) {
          // Non-initiator waited too long, try initiating ourselves
          debugPrint('CallController: Timeout waiting for caller, initiating reconnection');
          _isInitiator = true;
          _performFullReconnection();
        } else {
          debugPrint('CallController: Reconnection failed after all attempts');
          _updateStatus(CallStatus.failed);
          endCall(reason: 'reconnect_failed');
        }
      }
    });
  }

  Future<void> _handleSignal(WebRTCSignal signal) async {
    debugPrint('CallController: Handling signal: ${signal.signalType}');

    switch (signal.signalType) {
      case 'offer':
        await _handleOffer(signal.payload);
        break;
      case 'answer':
        await _handleAnswer(signal.payload);
        break;
      case 'ice_candidate':
        await _handleIceCandidate(signal.payload);
        break;
      case 'call_ended':
      case 'call_declined':
        await _handleRemoteHangup();
        break;
      case 'call_accepted':
        // Remote party accepted, we should be receiving answer soon
        debugPrint('CallController: Remote party accepted the call');
        break;
      // Note: 'reconnect' signal removed - callee detects reconnection from new offer
      default:
        debugPrint('CallController: Unknown signal type: ${signal.signalType}');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as String?;
    if (sdp == null) return;

    // If we're reconnecting or already connected, this is a reconnection offer
    // We need to reset our peer connection first
    if (_status == CallStatus.reconnecting || _status == CallStatus.connected) {
      debugPrint('CallController: Received reconnection offer, recreating peer connection');
      await _prepareForReconnection();
    }

    await _webrtcService.setRemoteDescription(sdp, 'offer');
    _remoteDescriptionSet = true;

    // Process queued ICE candidates
    await _processPendingIceCandidates();

    // Create and send answer
    if (_currentCall != null) {
      final answer = await _webrtcService.createAnswer();
      await _signalingService.sendAnswer(
        callId: _currentCall!.id,
        sdp: answer.sdp!,
      );
      debugPrint('CallController: Sent answer for reconnection');
    }
  }

  /// Prepare for reconnection by resetting peer connection state
  Future<void> _prepareForReconnection() async {
    debugPrint('CallController: Preparing peer connection for reconnection');
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();
    
    // Close old peer connection and create new one (preserving local stream)
    await _webrtcService.recreatePeerConnectionForCallee();
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final sdp = payload['sdp'] as String?;
    if (sdp == null) {
      debugPrint('CallController: _handleAnswer received null SDP');
      return;
    }

    debugPrint('CallController: Processing answer, setting remote description');
    
    // Stop polling since we have the answer
    _stopSignalPolling();
    
    await _webrtcService.setRemoteDescription(sdp, 'answer');
    _remoteDescriptionSet = true;

    // Process queued ICE candidates
    await _processPendingIceCandidates();
    
    // Handle reconnection completion
    if (_status == CallStatus.reconnecting) {
      debugPrint('CallController: Reconnection successful!');
      _onConnectionRestored();
    } else {
      // Normal call connection
      _updateStatus(CallStatus.connected);
      debugPrint('CallController: Answer processed, call is now connected');
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate'] as String?,
      payload['sdpMid'] as String?,
      payload['sdpMLineIndex'] as int?,
    );

    if (_remoteDescriptionSet) {
      await _webrtcService.addIceCandidate(candidate);
    } else {
      // Queue candidate for later
      _pendingIceCandidates.add(candidate);
    }
  }

  Future<void> _processPendingIceCandidates() async {
    for (final candidate in _pendingIceCandidates) {
      await _webrtcService.addIceCandidate(candidate);
    }
    _pendingIceCandidates.clear();
  }

  Future<void> _handleRemoteHangup() async {
    debugPrint('CallController: Remote party hung up');
    
    // Mark as intentional disconnect to prevent reconnection attempts
    _intentionalDisconnect = true;
    
    // Save to call history before cleanup
    if (_currentCall != null) {
      final updatedCall = await _signalingService.getCall(_currentCall!.id);
      if (updatedCall != null) {
        await _signalingService.saveCallToHistory(updatedCall);
      }
    }
    
    await _cleanup(CallStatus.ended);
  }

  /// Fetch and process any pending signals - fallback when realtime misses signals
  Future<void> _fetchAndProcessPendingSignals() async {
    if (_currentCall == null) return;
    
    try {
      debugPrint('CallController: Fetching pending signals as fallback');
      final pendingSignals = await _signalingService.fetchPendingSignals(
        _currentCall!.id,
      );
      
      for (final signal in pendingSignals) {
        // Only process if we haven't already (check for answer specifically)
        if (signal.signalType == 'answer' && !_remoteDescriptionSet) {
          debugPrint('CallController: Processing missed answer signal');
          await _handleSignal(signal);
        } else if (signal.signalType == 'ice_candidate') {
          await _handleSignal(signal);
        }
      }
    } catch (e) {
      debugPrint('CallController: Error fetching pending signals: $e');
    }
  }

  /// Start polling for signals as backup mechanism
  void _startSignalPolling() {
    _stopSignalPolling();
    // Poll every 2 seconds while in calling state
    _signalPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_status == CallStatus.calling && !_remoteDescriptionSet) {
        await _fetchAndProcessPendingSignals();
      } else {
        _stopSignalPolling();
      }
    });
  }

  void _stopSignalPolling() {
    _signalPollingTimer?.cancel();
    _signalPollingTimer = null;
  }

  void _listenToNotificationActions() {
    _notificationActionSubscription?.cancel();
    _notificationActionSubscription = CallNotifications.actions.listen((action) async {
      debugPrint('CallController: Notification action: ${action.action}, callId: ${action.callId}');
      
      switch (action.action.toLowerCase()) {
        case 'incoming_call':
          // Handle incoming call from FCM - set up call state
          if (action.callId != null && _status == CallStatus.idle) {
            await handleIncomingCallFromPush(action.callId!);
          }
          break;
        case 'answer':
          // If we don't have a call yet, try to set it up first
          if (_currentCall == null && action.callId != null) {
            await handleIncomingCallFromPush(action.callId!);
          }
          await acceptCall();
          break;
        case 'decline':
          if (_currentCall == null && action.callId != null) {
            await handleIncomingCallFromPush(action.callId!);
          }
          await declineCall();
          break;
        case 'hangup':
          await endCall();
          break;
        case 'timeout':
          if (_status == CallStatus.ringing) {
            await _cleanup(CallStatus.missed);
          } else if (_status == CallStatus.calling) {
            await endCall(reason: 'timeout');
          }
          break;
        case 'remote_accept':
          // Remote party accepted our call - fetch pending signals as fallback
          debugPrint('CallController: Remote party accepted the call');
          // Fetch signals if we have a call and haven't received the answer yet
          if (_currentCall != null && !_remoteDescriptionSet) {
            await _fetchAndProcessPendingSignals();
          }
          break;
        case 'remote_end':
          // Remote party ended or cancelled
          if (_status.isActive || _status.isRinging) {
            await _cleanup(CallStatus.ended);
          }
          break;
        case 'open':
          // User tapped notification to open call screen - load call state
          if (action.callId != null && _status == CallStatus.idle) {
            debugPrint('CallController: Loading call for open action: ${action.callId}');
            await handleIncomingCallFromPush(action.callId!);
          }
          break;
      }
    });

    // Check for pending startup action
    _checkPendingStartupAction();
  }

  /// Handle incoming call triggered by push notification
  /// This fetches call details from database and sets up the call state
  Future<void> handleIncomingCallFromPush(String callId) async {
    if (_status != CallStatus.idle) {
      debugPrint('CallController: Cannot handle incoming call - already busy');
      return;
    }

    try {
      // Fetch call details from active_calls
      _currentCall = await _signalingService.getCall(callId);
      if (_currentCall == null) {
        debugPrint('CallController: Call $callId not found in database');
        return;
      }

      debugPrint('CallController: Setting up incoming call ${_currentCall!.id}');
      _updateStatus(CallStatus.ringing);

      // Update call status to ringing
      await _signalingService.updateCallStatus(callId, 'ringing');

      // Initialize signaling
      await _signalingService.initialize(callId);
      _subscribeToSignals();
      _subscribeToCallUpdates();

      notifyListeners();
    } catch (e) {
      debugPrint('CallController: Error handling incoming call from push: $e');
      _error = e.toString();
      await _cleanup(CallStatus.failed);
    }
  }

  Future<void> _checkPendingStartupAction() async {
    final pending = await CallNotifications.getPendingStartupAction();
    if (pending != null) {
      debugPrint('CallController: Pending startup action: ${pending.action}, callId: ${pending.callId}');
      
      final action = pending.action.toLowerCase();
      
      // Only load call for actions that require it
      if (pending.callId != null && _status == CallStatus.idle) {
        switch (action) {
          case 'open':
          case 'incoming_call':
          case 'answer':
          case 'decline':
            debugPrint('CallController: Loading call ${pending.callId} for action: $action');
            await handleIncomingCallFromPush(pending.callId!);
            break;
          case 'remote_end':
          case 'timeout':
            debugPrint('CallController: Ignoring pending action $action - call already ended');
            return; // Don't process actions for ended calls
          default:
            break;
        }
      }
      
      // Emit the action to the notification stream
      CallNotifications.emitAction(pending);
      
      // Handle specific actions after a short delay to ensure UI is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        switch (action) {
          case 'answer':
            acceptCall();
            break;
          case 'decline':
            declineCall();
            break;
          case 'hangup':
            endCall();
            break;
        }
      });
    }
  }

  Future<void> _cleanup(CallStatus finalStatus) async {
    debugPrint('CallController: Cleaning up with status: $finalStatus');

    _stopDurationTimer();
    _stopSignalPolling();
    _reconnectTimer?.cancel();
    _reconnectTimeoutTimer?.cancel();
    _disconnectDelayTimer?.cancel();
    _reconnectAttempts = 0;
    _isInitiator = false;
    _intentionalDisconnect = false; // Reset for next call

    // Cancel subscriptions
    await _signalSubscription?.cancel();
    await _callUpdateSubscription?.cancel();
    await _iceCandidateSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _networkRestoredSubscription?.cancel();
    await _renegotiationSubscription?.cancel();
    await _iceConnectionStateSubscription?.cancel();

    _signalSubscription = null;
    _callUpdateSubscription = null;
    _iceCandidateSubscription = null;
    _connectionStateSubscription = null;
    _networkRestoredSubscription = null;
    _renegotiationSubscription = null;
    _iceConnectionStateSubscription = null;

    // Cleanup services
    await _webrtcService.cleanup();
    await _signalingService.leaveCall();

    // Cancel notifications
    if (_currentCall != null) {
      await CallNotifications.endCallNotification(_currentCall!.id);
    }
    await CallNotifications.stopForegroundService();
    
    // Close CallActivity (for Android)
    await CallNotifications.closeCallActivity();

    // Reset state
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;
    _currentCall = null;
    _connectedAt = null;
    _error = null;
    
    _updateStatus(finalStatus.isEnded ? CallStatus.idle : finalStatus);
    notifyListeners();
  }

  // === Push Notifications ===

  /// Get current user's name from profiles table (source of truth)
  Future<String> _getCurrentUserName() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Unknown';
    
    try {
      final response = await _client
          .from('profiles')
          .select('full_name, username')
          .eq('id', userId)
          .maybeSingle();
      
      if (response != null) {
        final name = response['full_name'] ?? response['username'];
        if (name != null && name.toString().isNotEmpty) {
          return name.toString();
        }
      }
    } catch (e) {
      debugPrint('CallController: Error fetching current user name: $e');
    }
    
    // Fallback to auth metadata or email
    final user = _client.auth.currentUser;
    final metadata = user?.userMetadata;
    final fallbackName = metadata?['full_name'] ?? 
                         metadata?['name'] ?? 
                         user?.email?.split('@').first;
    return fallbackName?.toString() ?? 'Unknown';
  }
  
  /// Get current user's avatar from profiles table (source of truth)
  Future<String?> _getCurrentUserAvatar() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    
    try {
      final response = await _client
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();
      
      return response?['avatar_url']?.toString();
    } catch (e) {
      debugPrint('CallController: Error fetching current user avatar: $e');
    }
    
    // Fallback to auth metadata
    return _client.auth.currentUser?.userMetadata?['avatar_url']?.toString();
  }

  Future<void> _sendCallInvitePush({
    required String calleeId,
    required String callerName,
    required String callId,
    required CallType callType,
    String? callerAvatar,
  }) async {
    try {
      await _client.functions.invoke('notify_call', body: {
        'recipient_id': calleeId,
        'type': 'call_invite',
        'session_id': callId,
        'caller_name': callerName,
        'call_type': callType.toDbString(),
        'avatar_url': callerAvatar,
      });
    } catch (e) {
      debugPrint('CallController: Error sending call invite push: $e');
    }
  }

  Future<void> _sendCallAcceptPush() async {
    if (_currentCall == null) return;
    
    try {
      final senderName = await _getCurrentUserName();
      final senderAvatar = await _getCurrentUserAvatar();
      await _client.functions.invoke('notify_call', body: {
        'recipient_id': _currentCall!.remoteUserId(currentUserId!),
        'type': 'call_accept',
        'session_id': _currentCall!.id,
        'sender_name': senderName,
        'avatar_url': senderAvatar,
      });
      debugPrint('CallController: Sent call_accept push to caller');
    } catch (e) {
      debugPrint('CallController: Error sending call accept push: $e');
    }
  }

  Future<void> _sendCallDeclinePush() async {
    if (_currentCall == null) return;
    
    try {
      await _client.functions.invoke('notify_call', body: {
        'recipient_id': _currentCall!.remoteUserId(currentUserId!),
        'type': 'call_decline',
        'session_id': _currentCall!.id,
      });
    } catch (e) {
      debugPrint('CallController: Error sending call decline push: $e');
    }
  }

  Future<void> _sendCallEndPush() async {
    if (_currentCall == null || currentUserId == null) return;
    
    try {
      await _client.functions.invoke('notify_call', body: {
        'recipient_id': _currentCall!.remoteUserId(currentUserId!),
        'type': 'call_end',
        'session_id': _currentCall!.id,
      });
    } catch (e) {
      debugPrint('CallController: Error sending call end push: $e');
    }
  }

  @override
  void dispose() {
    _notificationActionSubscription?.cancel();
    _cleanup(CallStatus.idle);
    super.dispose();
  }
}

/// Provider for the call controller
/// Note: Use ListenableBuilder in UI widgets to react to notifyListeners() calls
final callServiceProvider = Provider<CallController>((ref) {
  final client = ref.watch(supabaseProvider);
  final controller = CallController(client);
  ref.onDispose(() => controller.dispose());
  return controller;
});
