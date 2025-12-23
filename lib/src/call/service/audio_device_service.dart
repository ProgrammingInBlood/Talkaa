import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents an audio device
class AudioDevice {
  final String id;
  final String name;
  final String type;

  const AudioDevice({
    required this.id,
    required this.name,
    required this.type,
  });

  IconData get icon {
    switch (type) {
      case 'earpiece':
        return Icons.hearing_rounded;
      case 'speaker':
        return Icons.volume_up_rounded;
      case 'wired':
        return Icons.headset_rounded;
      case 'bluetooth':
        return Icons.bluetooth_audio_rounded;
      default:
        return Icons.volume_up_rounded;
    }
  }

  factory AudioDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioDevice(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'unknown',
    );
  }
}

/// Service for managing audio devices via native platform
class AudioDeviceService {
  static const MethodChannel _channel = MethodChannel('com.anonymous.talka/audio_devices');
  
  static bool _initialized = false;

  /// Initialize the audio device service
  static void init() {
    if (_initialized) return;
    _initialized = true;
    debugPrint('AudioDeviceService: Initialized');
  }

  /// Request Bluetooth permission (Android 12+)
  static Future<bool> requestBluetoothPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestBluetoothPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('AudioDeviceService: Error requesting Bluetooth permission: $e');
      return false;
    }
  }

  /// Get list of available audio devices
  static Future<List<AudioDevice>> getAudioDevices() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getAudioDevices');
      if (result == null) return _getDefaultDevices();
      
      return result.map((item) {
        if (item is Map) {
          return AudioDevice.fromMap(item);
        }
        return const AudioDevice(id: 'unknown', name: 'Unknown', type: 'unknown');
      }).toList();
    } catch (e) {
      debugPrint('AudioDeviceService: Error getting audio devices: $e');
      return _getDefaultDevices();
    }
  }

  /// Select an audio device by ID
  static Future<bool> selectAudioDevice(String deviceId) async {
    try {
      final result = await _channel.invokeMethod<bool>('selectAudioDevice', {
        'deviceId': deviceId,
      });
      debugPrint('AudioDeviceService: Selected device $deviceId');
      return result ?? false;
    } catch (e) {
      debugPrint('AudioDeviceService: Error selecting audio device: $e');
      return false;
    }
  }

  /// Get current audio device
  static Future<String> getCurrentAudioDevice() async {
    try {
      final result = await _channel.invokeMethod<String>('getCurrentAudioDevice');
      return result ?? 'earpiece';
    } catch (e) {
      debugPrint('AudioDeviceService: Error getting current audio device: $e');
      return 'earpiece';
    }
  }

  /// Get default devices when native call fails
  static List<AudioDevice> _getDefaultDevices() {
    return const [
      AudioDevice(id: 'earpiece', name: 'Phone Earpiece', type: 'earpiece'),
      AudioDevice(id: 'speaker', name: 'Speaker', type: 'speaker'),
    ];
  }
}
