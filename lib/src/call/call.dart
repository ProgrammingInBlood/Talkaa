/// Call module exports
/// 
/// Professional-grade video/voice calling feature using:
/// - WebRTC for peer-to-peer media
/// - Supabase Realtime for signaling (active_calls + webrtc_signals tables)
/// - Native Android foreground service for background calls
/// - Picture-in-Picture support
/// - Call history stored in 'calls' table
library;

// Models
export 'model/call_state.dart';
// ActiveCall and WebRTCSignal are defined in signaling_service.dart

// Services
export 'service/signaling_service.dart' show SignalingService, ActiveCall, WebRTCSignal;
export 'service/webrtc_service.dart';
export 'service/pip_service.dart';

// Core
export 'call_service.dart';
export 'call_manager.dart';

// UI
export 'ui/call_screen.dart';
export 'ui/widgets/call_controls.dart';
export 'ui/widgets/call_avatar.dart';
export 'ui/widgets/call_timer.dart';
export 'ui/widgets/incoming_call_controls.dart';
export 'ui/widgets/pip_video.dart';
