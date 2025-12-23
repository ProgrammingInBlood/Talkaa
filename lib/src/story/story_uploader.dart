import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';

class StoryUploader {
  static final ImagePicker _picker = ImagePicker();

  // Capture a photo from camera and upload to the 'stories' bucket. Returns public URL.
  static Future<String?> captureAndUpload(WidgetRef ref) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1440,
      maxHeight: 1440,
    );
    if (photo == null) return null;
    final bytes = await photo.readAsBytes();
    final filename = _fileName(photo);
    return _uploadBytes(ref, bytes, filename);
  }

  // Pick a photo from gallery and upload to the 'stories' bucket. Returns public URL.
  static Future<String?> pickFromGalleryAndUpload(WidgetRef ref) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1440,
      maxHeight: 1440,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    final filename = _fileName(image);
    return _uploadBytes(ref, bytes, filename);
  }

  static Future<String?> _uploadBytes(WidgetRef ref, Uint8List bytes, String filename) async {
    final client = ref.read(supabaseProvider);
    final bucket = client.storage.from('stories');
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;
    final path = '$uid/images/${DateTime.now().millisecondsSinceEpoch}_$filename';
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
    );
    return bucket.getPublicUrl(path);
  }

  static String _fileName(XFile file) {
    final base = (file.name.isNotEmpty ? file.name : 'story.jpg').replaceAll(' ', '_');
    return base;
  }
}