import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

// Cached current user's display name, preferring full_name > username > metadata name > email local part
final currentUserDisplayNameProvider = FutureProvider<String>((ref) async {
  final client = ref.read(supabaseProvider);
  final user = client.auth.currentUser;
  final emailLocal = (user?.email ?? '').split('@').first;
  if (user == null) {
    return emailLocal;
  }
  try {
    final row = await client
        .from('profiles')
        .select('full_name, username')
        .eq('id', user.id)
        .maybeSingle();
    final fullName = (row?['full_name'] as String?)?.trim();
    final username = (row?['username'] as String?)?.trim();
    final metaName = (user.userMetadata?['name'] as String?)?.trim();
    final raw = (fullName != null && fullName.isNotEmpty)
        ? fullName
        : (username != null && username.isNotEmpty)
            ? username
            : (metaName != null && metaName.isNotEmpty)
                ? metaName
                : emailLocal;
    return raw;
  } catch (_) {
    return emailLocal;
  }
});