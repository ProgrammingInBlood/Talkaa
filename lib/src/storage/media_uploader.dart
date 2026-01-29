import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_io/io.dart' as uio;
import '../providers.dart';

enum MediaSource { gallery, camera, file }

class MediaUploader {
  static final ImagePicker _imagePicker = ImagePicker();
  
  /// Show a bottom sheet to pick media source
  /// [chatId] is required for RLS policy - files are stored in {chatId}/ folder
  static Future<String?> showPickerAndUpload(BuildContext context, WidgetRef ref, {required String chatId}) async {
    final source = await showModalBottomSheet<MediaSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose Media',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: Theme.of(context).colorScheme.primary),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from your photos'),
                onTap: () => Navigator.pop(ctx, MediaSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_rounded, color: Theme.of(context).colorScheme.primary),
                title: const Text('Camera'),
                subtitle: const Text('Take a new photo'),
                onTap: () => Navigator.pop(ctx, MediaSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.attach_file_rounded, color: Theme.of(context).colorScheme.primary),
                title: const Text('File'),
                subtitle: const Text('Choose any file'),
                onTap: () => Navigator.pop(ctx, MediaSource.file),
              ),
            ],
          ),
        ),
      ),
    );
    
    if (source == null) return null;
    
    switch (source) {
      case MediaSource.gallery:
        return pickFromGalleryAndUpload(ref, chatId: chatId);
      case MediaSource.camera:
        return pickFromCameraAndUpload(ref, chatId: chatId);
      case MediaSource.file:
        return pickAndUpload(ref, chatId: chatId);
    }
  }
  
  /// Pick image from gallery and upload
  /// [chatId] is required for RLS policy - files are stored in {chatId}/ folder
  static Future<String?> pickFromGalleryAndUpload(WidgetRef ref, {required String chatId}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image == null) return null;
      return _uploadXFile(ref, image, chatId: chatId);
    } catch (e) {
      debugPrint('MediaUploader: Gallery pick error: $e');
      return null;
    }
  }
  
  /// Pick image from camera and upload
  /// [chatId] is required for RLS policy - files are stored in {chatId}/ folder
  static Future<String?> pickFromCameraAndUpload(WidgetRef ref, {required String chatId}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image == null) return null;
      return _uploadXFile(ref, image, chatId: chatId);
    } catch (e) {
      debugPrint('MediaUploader: Camera pick error: $e');
      return null;
    }
  }
  
  /// Upload XFile to Supabase
  /// [chatId] is required for RLS policy - files are stored in {chatId}/ folder
  static Future<String?> _uploadXFile(WidgetRef ref, XFile file, {required String chatId}) async {
    try {
      final client = ref.read(supabaseProvider);
      final uid = client.auth.currentUser?.id;
      debugPrint('MediaUploader: User ID: $uid, Chat ID: $chatId');
      
      final bucket = client.storage.from('chat-files');
      final ext = file.name.split('.').last.toLowerCase();
      // Use chat ID in path for RLS policy (policy checks if user is participant in this chat)
      final path = '$chatId/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      debugPrint('MediaUploader: Upload path: $path');
      
      final bytes = await file.readAsBytes();
      final contentType = _getContentType(ext);
      debugPrint('MediaUploader: Content type: $contentType, Size: ${bytes.length}');
      
      await bucket.uploadBinary(
        path, 
        bytes, 
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
      
      // Store only the path, not full URL (signed URLs generated on display)
      debugPrint('MediaUploader: Upload success, path: $path');
      return path;
    } catch (e, stack) {
      debugPrint('MediaUploader: Upload error: $e');
      debugPrint('MediaUploader: Stack: $stack');
      return null;
    }
  }
  
  /// Get content type from file extension
  static String _getContentType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/*';
    }
  }

  /// Legacy method - pick file and upload
  /// [chatId] is required for RLS policy - files are stored in {chatId}/ folder
  static Future<String?> pickAndUpload(WidgetRef ref, {required String chatId}) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return null;
      final picked = result.files.single;
      final client = ref.read(supabaseProvider);
      final uid = client.auth.currentUser?.id;
      debugPrint('MediaUploader(file): User ID: $uid, Chat ID: $chatId');
      
      final bucket = client.storage.from('chat-files');
      final path = '$chatId/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
      debugPrint('MediaUploader(file): Upload path: $path');
      
      if (picked.bytes != null) {
        final ext = picked.name.split('.').last.toLowerCase();
        await bucket.uploadBinary(
          path, 
          picked.bytes!, 
          fileOptions: FileOptions(upsert: true, contentType: _getContentType(ext)),
        );
      } else if (picked.path != null) {
        await bucket.upload(path, uio.File(picked.path!));
      } else {
        return null;
      }
      // Store only the path, not full URL (signed URLs generated on display)
      debugPrint('MediaUploader(file): Upload success, path: $path');
      return path;
    } catch (e, stack) {
      debugPrint('MediaUploader(file): Upload error: $e');
      debugPrint('MediaUploader(file): Stack: $stack');
      return null;
    }
  }
}