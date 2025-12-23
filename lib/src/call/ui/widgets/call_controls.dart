import 'package:flutter/material.dart';
import '../../model/call_state.dart';
import '../../call_service.dart';
import '../../service/audio_device_service.dart';

const _themeGreen = Color(0xFF659254);

/// Control buttons for an active call
class CallControls extends StatelessWidget {
  final bool isMuted;
  final bool isVideoEnabled;
  final bool isSpeakerOn;
  final CallType callType;
  final VoidCallback onMuteToggle;
  final VoidCallback onVideoToggle;
  final VoidCallback onSpeakerToggle;
  final VoidCallback onCameraSwitch;
  final VoidCallback onEndCall;
  final CallController? controller;

  const CallControls({
    super.key,
    required this.isMuted,
    required this.isVideoEnabled,
    required this.isSpeakerOn,
    required this.callType,
    required this.onMuteToggle,
    required this.onVideoToggle,
    required this.onSpeakerToggle,
    required this.onCameraSwitch,
    required this.onEndCall,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute button with long press for mic selection
          _MicDeviceButton(
            isMuted: isMuted,
            onTap: onMuteToggle,
            controller: controller,
          ),
          
          // Video button (for video calls)
          if (callType == CallType.video)
            _ControlButton(
              icon: isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: isVideoEnabled ? 'Video' : 'Video',
              isActive: !isVideoEnabled,
              activeColor: Colors.red.shade400,
              onTap: onVideoToggle,
            ),
          
          // Speaker button with long press for device selection
          _AudioDeviceButton(
            isSpeakerOn: isSpeakerOn,
            onTap: onSpeakerToggle,
            controller: controller,
          ),
          
          // Camera switch button (for video calls)
          if (callType == CallType.video && isVideoEnabled)
            _ControlButton(
              icon: Icons.cameraswitch_rounded,
              label: 'Flip',
              isActive: false,
              onTap: onCameraSwitch,
            ),
          
          // End call button
          _EndCallButton(onTap: onEndCall),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive
        ? (activeColor ?? Colors.white)
        : Colors.white.withValues(alpha: 0.12);
    final iconColor = isActive
        ? Colors.white
        : Colors.white.withValues(alpha: 0.9);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: (activeColor ?? Colors.white).withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'End',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio output device button with long press to show device picker
class _AudioDeviceButton extends StatelessWidget {
  final bool isSpeakerOn;
  final VoidCallback onTap;
  final CallController? controller;

  const _AudioDeviceButton({
    required this.isSpeakerOn,
    required this.onTap,
    this.controller,
  });

  void _showAudioOutputPicker(BuildContext context) async {
    // Request Bluetooth permission first
    await AudioDeviceService.requestBluetoothPermission();
    
    // Get devices from native platform
    final devices = await AudioDeviceService.getAudioDevices();
    final currentDevice = await AudioDeviceService.getCurrentAudioDevice();
    if (!context.mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Audio Output',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ...devices.map((device) => ListTile(
                leading: Icon(
                  _getIconForDevice(device.type),
                  color: Colors.white,
                ),
                title: Text(
                  device.name,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: currentDevice == device.id ||
                        (currentDevice == 'bluetooth' && device.type == 'bluetooth')
                    ? const Icon(Icons.check, color: _themeGreen)
                    : null,
                onTap: () async {
                  await AudioDeviceService.selectAudioDevice(device.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForDevice(String deviceType) {
    switch (deviceType) {
      case 'earpiece':
        return Icons.hearing_rounded;
      case 'speaker':
        return Icons.volume_up_rounded;
      case 'wired':
        return Icons.headset_rounded;
      case 'bluetooth':
        return Icons.bluetooth_audio_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isSpeakerOn
        ? _themeGreen
        : Colors.white.withValues(alpha: 0.12);
    final iconColor = isSpeakerOn
        ? Colors.white
        : Colors.white.withValues(alpha: 0.9);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showAudioOutputPicker(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: isSpeakerOn
                  ? [
                      BoxShadow(
                        color: _themeGreen.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isSpeakerOn ? 'Speaker' : 'Earpiece',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Microphone device button with long press to show device picker
class _MicDeviceButton extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onTap;
  final CallController? controller;

  const _MicDeviceButton({
    required this.isMuted,
    required this.onTap,
    this.controller,
  });

  void _showMicPicker(BuildContext context) async {
    // Request Bluetooth permission first
    await AudioDeviceService.requestBluetoothPermission();
    
    // Get devices from native platform
    final devices = await AudioDeviceService.getAudioDevices();
    final currentDevice = await AudioDeviceService.getCurrentAudioDevice();
    if (!context.mounted) return;
    
    // Build mic options - only devices that actually have microphones
    final List<AudioDevice> allMicOptions = [
      const AudioDevice(id: 'default', name: 'Phone Microphone', type: 'default'),
    ];
    
    // Add wired headset if connected (has mic)
    final hasWired = devices.any((d) => d.type == 'wired');
    if (hasWired) {
      allMicOptions.add(const AudioDevice(id: 'wired', name: 'Wired Headset Mic', type: 'wired'));
    }
    
    // Add Bluetooth devices if connected (have mic)
    final bluetoothDevices = devices.where((d) => d.type == 'bluetooth').toList();
    for (final bt in bluetoothDevices) {
      allMicOptions.add(AudioDevice(id: bt.id, name: '${bt.name} Mic', type: 'bluetooth'));
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Microphone',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Microphone follows audio output routing',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              ...allMicOptions.map((device) => ListTile(
                leading: Icon(
                  _getMicIcon(device.type),
                  color: Colors.white,
                ),
                title: Text(
                  device.name,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: _isCurrentMic(device.type, currentDevice)
                    ? const Icon(Icons.check, color: _themeGreen)
                    : null,
                onTap: () async {
                  // Selecting mic routes audio to corresponding device
                  if (device.type == 'default') {
                    // Phone mic uses earpiece for audio
                    await AudioDeviceService.selectAudioDevice('earpiece');
                  } else {
                    await AudioDeviceService.selectAudioDevice(device.id);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
  
  bool _isCurrentMic(String deviceType, String currentDevice) {
    switch (deviceType) {
      case 'default':
        // Phone mic is active when using earpiece or speaker
        return currentDevice == 'earpiece' || currentDevice == 'speaker';
      case 'wired':
        return currentDevice == 'wired';
      case 'bluetooth':
        return currentDevice == 'bluetooth';
      default:
        return false;
    }
  }
  
  IconData _getMicIcon(String deviceType) {
    switch (deviceType) {
      case 'default':
        return Icons.mic_rounded;
      case 'wired':
        return Icons.headset_mic_rounded;
      case 'bluetooth':
        return Icons.bluetooth_audio_rounded;
      default:
        return Icons.mic_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isMuted
        ? Colors.red.shade400
        : Colors.white.withValues(alpha: 0.12);
    final iconColor = isMuted
        ? Colors.white
        : Colors.white.withValues(alpha: 0.9);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showMicPicker(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: isMuted
                  ? [
                      BoxShadow(
                        color: Colors.red.shade400.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isMuted ? 'Unmute' : 'Mute',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
