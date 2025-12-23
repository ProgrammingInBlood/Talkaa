import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class AutoStartHelper {
  static const MethodChannel _channel = MethodChannel('com.anonymous.talka/autostart');

  static Future<bool> isAutoStartAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAutoStartAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAutoStartSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAutoStartSettings');
    } catch (_) {}
  }

  static Future<void> showAutoStartDialog(BuildContext context) async {
    if (!Platform.isAndroid) return;
    
    final available = await isAutoStartAvailable();
    if (!available) return;
    if (!context.mounted) return;

    final cs = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.notifications_active, color: cs.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enable Auto-Start',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To receive incoming call notifications when the app is closed, please enable auto-start for Talka in your device settings.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This helps with:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildBullet('Receiving calls when app is closed', cs),
                  _buildBullet('Getting message notifications', cs),
                  _buildBullet('Staying connected in background', cs),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAutoStartSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static Widget _buildBullet(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
