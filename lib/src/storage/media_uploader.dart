import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart' as uio;
import '../providers.dart';

class MediaUploader {
  static Future<String?> pickAndUpload(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final client = ref.read(supabaseProvider);
    final bucket = client.storage.from('chat-media');
    final path = 'images/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
    if (picked.bytes != null) {
      await bucket.uploadBinary(path, picked.bytes!, fileOptions: const FileOptions(upsert: true, contentType: 'image/*'));
    } else if (picked.path != null) {
      await bucket.upload(path, uio.File(picked.path!));
    } else {
      return null;
    }
    final publicUrl = bucket.getPublicUrl(path);
    return publicUrl;
  }
}