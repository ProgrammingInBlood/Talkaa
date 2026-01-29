import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../providers.dart';
import '../storage/signed_url_helper.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  
  File? _selectedImage;
  String? _currentAvatarUrl;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _usernameError;
  String? _originalUsername;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final row = await client
          .from('profiles')
          .select('full_name, username, bio, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      if (row != null && mounted) {
        // Sign avatar URL
        String? signedAvatarUrl = row['avatar_url'] as String?;
        if (signedAvatarUrl != null && signedAvatarUrl.isNotEmpty) {
          signedAvatarUrl = await SignedUrlHelper.getAvatarUrl(client, signedAvatarUrl);
        }
        
        setState(() {
          _nameController.text = (row['full_name'] as String?) ?? '';
          _usernameController.text = (row['username'] as String?) ?? '';
          _originalUsername = (row['username'] as String?) ?? '';
          _bioController.text = (row['bio'] as String?) ?? '';
          _currentAvatarUrl = signedAvatarUrl;
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<bool> _checkUsernameAvailability(String username) async {
    if (username.isEmpty) return false;
    if (username.toLowerCase() == _originalUsername?.toLowerCase()) return true;
    
    try {
      final client = ref.read(supabaseProvider);
      final result = await client
          .from('profiles')
          .select('username')
          .eq('username', username.toLowerCase())
          .limit(1);
      
      return result.isEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _uploadAvatar() async {
    if (_selectedImage == null) return _currentAvatarUrl;
    
    try {
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;
      
      final fileName = '$userId/avatar.jpg';
      final bytes = await _selectedImage!.readAsBytes();
      
      debugPrint('Uploading avatar to: avatar/$fileName');
      
      final uploadResult = await client.storage
          .from('avatar')
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));
      
      debugPrint('Upload result: $uploadResult');
      
      // Store only the path, not full URL (signed URLs generated on display)
      debugPrint('Stored path: $fileName');
      
      return fileName;
    } catch (e) {
      debugPrint('Error uploading avatar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${e.toString()}')),
        );
      }
      return _currentAvatarUrl;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _usernameError = null;
    });

    try {
      final username = _usernameController.text.trim().toLowerCase();
      
      // Check username availability if changed
      if (username != _originalUsername?.toLowerCase()) {
        final isUsernameAvailable = await _checkUsernameAvailability(username);
        if (!isUsernameAvailable) {
          setState(() {
            _usernameError = 'Username is already taken';
            _isLoading = false;
          });
          return;
        }
      }

      // Upload avatar if changed
      final avatarUrl = await _uploadAvatar();

      // Update profile
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser?.id;
      
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await client.from('profiles').update({
        'username': username,
        'full_name': _nameController.text.trim(),
        'bio': _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          if (_isInitialized)
            TextButton(
              onPressed: _isLoading ? null : _saveProfile,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: cs.primaryContainer,
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!)
                                : (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty)
                                    ? NetworkImage(_currentAvatarUrl!)
                                    : null,
                            child: (_selectedImage == null &&
                                    (_currentAvatarUrl == null || _currentAvatarUrl!.isEmpty))
                                ? Icon(Icons.person, size: 48, color: cs.onPrimaryContainer)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: cs.surface, width: 2),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to change photo',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.alternate_email),
                        errorText: _usernameError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a username';
                        }
                        if (value.trim().length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                          return 'Username can only contain letters, numbers, and underscores';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bioController,
                      maxLines: 3,
                      maxLength: 150,
                      decoration: InputDecoration(
                        labelText: 'Bio',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 48),
                          child: Icon(Icons.info_outline),
                        ),
                        hintText: 'Write something about yourself...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
