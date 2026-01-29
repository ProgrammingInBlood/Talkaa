import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../model/call_state.dart';

/// Configuration for WebRTC connections
class WebRTCConfig {
  static const Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
      {
        'urls': 'turn:in.relay.metered.ca:80',
        'username': '8179404ce601cabc2f7cfc35',
        'credential': 'hSP6Kboe7bnR41qz',
      },
      {
        'urls': 'turn:in.relay.metered.ca:80?transport=tcp',
        'username': '8179404ce601cabc2f7cfc35',
        'credential': 'hSP6Kboe7bnR41qz',
      },
      {
        'urls': 'turn:in.relay.metered.ca:443',
        'username': '8179404ce601cabc2f7cfc35',
        'credential': 'hSP6Kboe7bnR41qz',
      },
      {
        'urls': 'turns:in.relay.metered.ca:443?transport=tcp',
        'username': '8179404ce601cabc2f7cfc35',
        'credential': 'hSP6Kboe7bnR41qz',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 2,
  };

  static const Map<String, dynamic> offerSdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  static const Map<String, dynamic> loopbackConstraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };
}

/// Service for managing WebRTC peer connection and media streams
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _iceCandidateController = StreamController<RTCIceCandidate>.broadcast();
  final _connectionStateController = StreamController<RTCPeerConnectionState>.broadcast();
  final _renegotiationNeededController = StreamController<void>.broadcast();
  final _iceConnectionStateController = StreamController<RTCIceConnectionState>.broadcast();
  
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  CallType _callType = CallType.audio;
  bool _isReconnecting = false;
  
  // Network connectivity monitoring
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasConnected = true;
  final _networkRestoredController = StreamController<void>.broadcast();

  /// Whether we're currently in a reconnection attempt
  bool get isReconnecting => _isReconnecting;
  
  /// Stream that fires when network connectivity is restored
  Stream<void> get networkRestored => _networkRestoredController.stream;
  
  /// Stream that fires when renegotiation is needed
  Stream<void> get renegotiationNeeded => _renegotiationNeededController.stream;
  
  /// Stream of ICE connection state changes (more reliable on mobile)
  Stream<RTCIceConnectionState> get iceConnectionState => _iceConnectionStateController.stream;

  /// Stream of local media
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  
  /// Stream of remote media
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;
  
  /// Stream of ICE candidates to send
  Stream<RTCIceCandidate> get iceCandidates => _iceCandidateController.stream;
  
  /// Stream of connection state changes
  Stream<RTCPeerConnectionState> get connectionState => 
      _connectionStateController.stream;

  /// Current local stream
  MediaStream? get currentLocalStream => _localStream;
  
  /// Current remote stream
  MediaStream? get currentRemoteStream => _remoteStream;
  
  /// Current mute state
  bool get isMuted => _isMuted;
  
  /// Current video state
  bool get isVideoEnabled => _isVideoEnabled;
  
  /// Current speaker state
  bool get isSpeakerOn => _isSpeakerOn;
  
  /// Current camera position
  bool get isFrontCamera => _isFrontCamera;
  
  /// Current call type
  CallType get callType => _callType;

  /// Initialize WebRTC for a call
  Future<void> initialize(CallType type) async {
    _callType = type;
    await _createPeerConnection();
    await _getUserMedia(type);
    _startNetworkMonitoring();
  }
  
  /// Start monitoring network connectivity
  void _startNetworkMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.isNotEmpty && 
          !results.contains(ConnectivityResult.none);
      
      debugPrint('WebRTCService: Network connectivity changed: $results, connected: $isConnected');
      
      // Detect network restoration
      if (!_wasConnected && isConnected) {
        debugPrint('WebRTCService: Network restored!');
        _networkRestoredController.add(null);
      }
      
      _wasConnected = isConnected;
    });
  }

  /// Create the peer connection
  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(
      WebRTCConfig.configuration,
      WebRTCConfig.loopbackConstraints,
    );

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('WebRTCService: ICE candidate generated');
      _iceCandidateController.add(candidate);
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('WebRTCService: ICE connection state: $state');
      
      // Emit ICE connection state directly for more reliable monitoring
      _iceConnectionStateController.add(state);
      
      // Also map ICE connection state to peer connection state as fallback
      // because onConnectionState doesn't fire reliably on all platforms
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _connectionStateController.add(
            RTCPeerConnectionState.RTCPeerConnectionStateConnected,
          );
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _connectionStateController.add(
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
          );
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _connectionStateController.add(
            RTCPeerConnectionState.RTCPeerConnectionStateFailed,
          );
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _connectionStateController.add(
            RTCPeerConnectionState.RTCPeerConnectionStateClosed,
          );
          break;
        default:
          break;
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTCService: Connection state: $state');
      // Still emit for platforms where this works properly
      _connectionStateController.add(state);
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      debugPrint('WebRTCService: Remote track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
      }
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('WebRTCService: Remote stream added');
      _remoteStream = stream;
      _remoteStreamController.add(_remoteStream);
    };

    _peerConnection!.onRemoveStream = (MediaStream stream) {
      debugPrint('WebRTCService: Remote stream removed');
      _remoteStream = null;
      _remoteStreamController.add(null);
    };
    
    // Important: Handle renegotiation needed for ICE restart
    _peerConnection!.onRenegotiationNeeded = () {
      debugPrint('WebRTCService: Renegotiation needed');
      _renegotiationNeededController.add(null);
    };
  }

  /// Get user media (camera/microphone) with adaptive quality for Android Go
  Future<void> _getUserMedia(CallType type) async {
    // Use lower resolution for better performance on low-end devices
    // Android Go devices typically have limited RAM and processing power
    final Map<String, dynamic> constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': type == CallType.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640, 'max': 1280},
              'height': {'ideal': 480, 'max': 720},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStreamController.add(_localStream);

      // Add tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _isVideoEnabled = type == CallType.video;
      debugPrint('WebRTCService: Local stream acquired');
    } catch (e) {
      debugPrint('WebRTCService: Error getting user media: $e');
      rethrow;
    }
  }

  /// Create an SDP offer
  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    final offer = await _peerConnection!.createOffer(
      WebRTCConfig.offerSdpConstraints,
    );
    await _peerConnection!.setLocalDescription(offer);
    debugPrint('WebRTCService: Offer created');
    return offer;
  }

  /// Create an SDP answer
  Future<RTCSessionDescription> createAnswer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    debugPrint('WebRTCService: Answer created');
    return answer;
  }

  /// Set remote description (offer or answer)
  Future<void> setRemoteDescription(String sdp, String type) async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    final description = RTCSessionDescription(sdp, type);
    await _peerConnection!.setRemoteDescription(description);
    debugPrint('WebRTCService: Remote description set ($type)');
  }

  /// Add ICE candidate from remote peer
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) {
      debugPrint('WebRTCService: Cannot add ICE candidate - no peer connection');
      return;
    }

    try {
      await _peerConnection!.addCandidate(candidate);
      debugPrint('WebRTCService: ICE candidate added');
    } catch (e) {
      debugPrint('WebRTCService: Error adding ICE candidate: $e');
    }
  }

  /// Toggle microphone mute
  Future<void> toggleMute() async {
    if (_localStream == null) return;

    _isMuted = !_isMuted;
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    debugPrint('WebRTCService: Mute toggled: $_isMuted');
  }

  /// Set mute state explicitly
  Future<void> setMute(bool muted) async {
    if (_localStream == null) return;

    _isMuted = muted;
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  /// Toggle video on/off
  Future<void> toggleVideo() async {
    if (_localStream == null) return;

    _isVideoEnabled = !_isVideoEnabled;
    _localStream!.getVideoTracks().forEach((track) {
      track.enabled = _isVideoEnabled;
    });
    debugPrint('WebRTCService: Video toggled: $_isVideoEnabled');
  }

  /// Set video state explicitly
  Future<void> setVideo(bool enabled) async {
    if (_localStream == null) return;

    _isVideoEnabled = enabled;
    _localStream!.getVideoTracks().forEach((track) {
      track.enabled = _isVideoEnabled;
    });
  }

  /// Toggle speaker/earpiece
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
      debugPrint('WebRTCService: Speaker toggled: $_isSpeakerOn');
    } catch (e) {
      debugPrint('WebRTCService: Error toggling speaker: $e');
    }
  }

  /// Set speaker on/off explicitly
  Future<void> setSpeakerOn(bool enabled) async {
    _isSpeakerOn = enabled;
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
      debugPrint('WebRTCService: Speaker set to: $_isSpeakerOn');
    } catch (e) {
      debugPrint('WebRTCService: Error setting speaker: $e');
    }
  }

  /// Get available audio output devices
  Future<List<MediaDeviceInfo>> getAudioOutputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      return devices.where((d) => d.kind == 'audiooutput').toList();
    } catch (e) {
      debugPrint('WebRTCService: Error getting audio output devices: $e');
      return [];
    }
  }

  /// Get available audio input devices (microphones)
  Future<List<MediaDeviceInfo>> getAudioInputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      return devices.where((d) => d.kind == 'audioinput').toList();
    } catch (e) {
      debugPrint('WebRTCService: Error getting audio input devices: $e');
      return [];
    }
  }

  /// Select audio output device by ID
  Future<void> selectAudioOutput(String deviceId) async {
    try {
      // For mobile, we use Helper methods
      // deviceId convention: 'speaker', 'earpiece', 'bluetooth'
      if (deviceId == 'speaker') {
        await Helper.setSpeakerphoneOn(true);
        _isSpeakerOn = true;
      } else {
        await Helper.setSpeakerphoneOn(false);
        _isSpeakerOn = false;
      }
      debugPrint('WebRTCService: Audio output selected: $deviceId');
    } catch (e) {
      debugPrint('WebRTCService: Error selecting audio output: $e');
    }
  }

  /// Select audio input device by ID
  Future<void> selectAudioInput(String deviceId) async {
    try {
      if (_localStream == null) return;
      
      // Get new audio stream with selected device
      final constraints = {
        'audio': {'deviceId': deviceId},
        'video': false,
      };
      
      final newStream = await navigator.mediaDevices.getUserMedia(constraints);
      final newAudioTrack = newStream.getAudioTracks().first;
      
      // Replace audio track in local stream
      final oldAudioTracks = _localStream!.getAudioTracks();
      for (final track in oldAudioTracks) {
        _localStream!.removeTrack(track);
        track.stop();
      }
      _localStream!.addTrack(newAudioTrack);
      
      // Replace track in peer connection
      if (_peerConnection != null) {
        final senders = await _peerConnection!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'audio') {
            await sender.replaceTrack(newAudioTrack);
            break;
          }
        }
      }
      
      debugPrint('WebRTCService: Audio input selected: $deviceId');
    } catch (e) {
      debugPrint('WebRTCService: Error selecting audio input: $e');
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (_localStream == null) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isEmpty) return;

    try {
      await Helper.switchCamera(videoTracks.first);
      _isFrontCamera = !_isFrontCamera;
      debugPrint('WebRTCService: Camera switched');
    } catch (e) {
      debugPrint('WebRTCService: Error switching camera: $e');
    }
  }

  /// Enable video (upgrade from audio call)
  Future<void> enableVideo() async {
    if (_localStream == null || _peerConnection == null) return;
    if (_callType == CallType.video && _isVideoEnabled) return;

    try {
      // If upgrading from audio, need to get video track
      if (_callType == CallType.audio) {
        final videoStream = await navigator.mediaDevices.getUserMedia({
          'video': {
            'facingMode': 'user',
            'width': {'ideal': 1280},
            'height': {'ideal': 720},
          },
        });

        final videoTrack = videoStream.getVideoTracks().first;
        _localStream!.addTrack(videoTrack);
        _peerConnection!.addTrack(videoTrack, _localStream!);
        _callType = CallType.video;
      }

      _isVideoEnabled = true;
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = true;
      });
      _localStreamController.add(_localStream);
      debugPrint('WebRTCService: Video enabled');
    } catch (e) {
      debugPrint('WebRTCService: Error enabling video: $e');
    }
  }

  /// Restart ICE to attempt reconnection
  Future<RTCSessionDescription?> restartIce() async {
    if (_peerConnection == null) {
      debugPrint('WebRTCService: Cannot restart ICE - no peer connection');
      return null;
    }

    try {
      debugPrint('WebRTCService: Restarting ICE...');
      _isReconnecting = true;
      
      // Create a new offer with ICE restart flag
      final offer = await _peerConnection!.createOffer({
        ...WebRTCConfig.offerSdpConstraints,
        'iceRestart': true,
      });
      
      await _peerConnection!.setLocalDescription(offer);
      debugPrint('WebRTCService: ICE restart offer created');
      return offer;
    } catch (e) {
      debugPrint('WebRTCService: Error restarting ICE: $e');
      _isReconnecting = false;
      return null;
    }
  }

  /// Full peer connection recreation - used when ICE restart fails
  /// This preserves the local stream but recreates the peer connection
  Future<RTCSessionDescription?> recreatePeerConnection() async {
    if (_localStream == null) {
      debugPrint('WebRTCService: Cannot recreate - no local stream');
      return null;
    }

    try {
      debugPrint('WebRTCService: Recreating peer connection...');
      _isReconnecting = true;
      
      // Close old peer connection
      await _peerConnection?.close();
      _peerConnection = null;
      
      // Create new peer connection
      await _createPeerConnection();
      
      // Re-add local tracks to new peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      // Create new offer
      final offer = await _peerConnection!.createOffer(
        WebRTCConfig.offerSdpConstraints,
      );
      await _peerConnection!.setLocalDescription(offer);
      
      debugPrint('WebRTCService: Peer connection recreated, new offer created');
      return offer;
    } catch (e) {
      debugPrint('WebRTCService: Error recreating peer connection: $e');
      _isReconnecting = false;
      return null;
    }
  }

  /// Recreate peer connection for callee (doesn't create offer, waits for one)
  Future<void> recreatePeerConnectionForCallee() async {
    if (_localStream == null) {
      debugPrint('WebRTCService: Cannot recreate for callee - no local stream');
      return;
    }

    try {
      debugPrint('WebRTCService: Recreating peer connection for callee...');
      _isReconnecting = true;
      
      // Close old peer connection
      await _peerConnection?.close();
      _peerConnection = null;
      
      // Create new peer connection
      await _createPeerConnection();
      
      // Re-add local tracks to new peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      debugPrint('WebRTCService: Peer connection recreated for callee, ready for offer');
    } catch (e) {
      debugPrint('WebRTCService: Error recreating peer connection for callee: $e');
      _isReconnecting = false;
    }
  }

  /// Mark reconnection as complete
  void reconnectionComplete() {
    _isReconnecting = false;
    debugPrint('WebRTCService: Reconnection complete');
  }

  /// Get connection statistics
  Future<Map<String, dynamic>> getStats() async {
    if (_peerConnection == null) return {};

    try {
      final stats = await _peerConnection!.getStats();
      final result = <String, dynamic>{};
      
      for (final report in stats) {
        if (report.type == 'inbound-rtp' || report.type == 'outbound-rtp') {
          result[report.id] = report.values;
        }
      }
      
      return result;
    } catch (e) {
      debugPrint('WebRTCService: Error getting stats: $e');
      return {};
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    debugPrint('WebRTCService: Disposing...');

    // Stop all tracks
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _remoteStream?.dispose();
    _remoteStream = null;

    // Close peer connection
    await _peerConnection?.close();
    _peerConnection = null;

    // Reset state
    _isMuted = false;
    _isVideoEnabled = true;
    _isSpeakerOn = true;
    _isFrontCamera = true;

    // Cancel subscriptions
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    // Close streams
    await _localStreamController.close();
    await _remoteStreamController.close();
    await _iceCandidateController.close();
    await _connectionStateController.close();
    await _renegotiationNeededController.close();
    await _networkRestoredController.close();
    await _iceConnectionStateController.close();

    debugPrint('WebRTCService: Disposed');
  }

  /// Clean up for a single call without closing broadcast streams
  Future<void> cleanup() async {
    debugPrint('WebRTCService: Cleaning up...');

    // Stop all tracks
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream?.dispose();
    _localStream = null;
    _localStreamController.add(null);

    _remoteStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _remoteStream?.dispose();
    _remoteStream = null;
    _remoteStreamController.add(null);

    // Close peer connection
    await _peerConnection?.close();
    _peerConnection = null;

    // Cancel connectivity monitoring
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    // Reset state
    _isMuted = false;
    _isVideoEnabled = true;
    _isSpeakerOn = true;
    _isFrontCamera = true;
    _isReconnecting = false;
    _wasConnected = true;

    debugPrint('WebRTCService: Cleaned up');
  }
}
