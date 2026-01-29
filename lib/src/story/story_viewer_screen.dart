import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'story_service.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> stories;
  final int initialIndex;
  final bool isOwnStory;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    this.isOwnStory = false,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;
  int _currentIndex = 0;
  // ignore: unused_field
  bool _isPaused = false;
  bool _showViewers = false;
  List<Map<String, dynamic>> _viewers = [];
  bool _loadingViewers = false;

  static const _storyDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _progressController = AnimationController(
      vsync: this,
      duration: _storyDuration,
    );

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _startProgress();
    _markCurrentAsViewed();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _startProgress() {
    _progressController.forward(from: 0);
  }

  void _pauseProgress() {
    _progressController.stop();
    _isPaused = true;
  }

  void _resumeProgress() {
    _progressController.forward();
    _isPaused = false;
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _progressController.forward(from: 0);
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _showViewers = false;
    });
    _startProgress();
    _markCurrentAsViewed();
  }

  Future<void> _markCurrentAsViewed() async {
    if (widget.isOwnStory) return;
    final storyId = widget.stories[_currentIndex]['id']?.toString();
    if (storyId != null) {
      final svc = ref.read(StoryService.storyServiceProvider);
      await svc.markViewed(storyId: storyId);
    }
  }

  Future<void> _loadViewers() async {
    if (_loadingViewers) return;
    setState(() => _loadingViewers = true);

    try {
      final storyId = widget.stories[_currentIndex]['id']?.toString();
      if (storyId != null) {
        final svc = ref.read(StoryService.storyServiceProvider);
        final viewers = await svc.fetchStoryViewers(storyId);
        setState(() {
          _viewers = viewers;
          _loadingViewers = false;
        });
      }
    } catch (e) {
      setState(() => _loadingViewers = false);
    }
  }

  void _toggleViewers() {
    if (!widget.isOwnStory) return;
    
    if (_showViewers) {
      setState(() => _showViewers = false);
      _resumeProgress();
    } else {
      _pauseProgress();
      _loadViewers();
      setState(() => _showViewers = true);
    }
  }

  Future<void> _deleteStory() async {
    final storyId = widget.stories[_currentIndex]['id']?.toString();
    if (storyId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Story'),
        content: const Text('Are you sure you want to delete this story?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final svc = ref.read(StoryService.storyServiceProvider);
      final success = await svc.deleteStory(storyId);
      if (success && mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];
    final userMap = (story['user'] as Map<String, dynamic>?) ?? {};
    final userName = userMap['full_name'] ?? userMap['username'] ?? 'Story';
    final userAvatar = userMap['avatar_url'] as String?;
    final createdAt = story['created_at']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (_) => _pauseProgress(),
        onTapUp: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _previousStory();
          } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
            _nextStory();
          } else {
            _resumeProgress();
          }
        },
        onLongPressStart: (_) => _pauseProgress(),
        onLongPressEnd: (_) => _resumeProgress(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.stories.length,
              itemBuilder: (context, index) {
                final item = widget.stories[index];
                final url = item['media_url']?.toString() ?? '';
                return Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: List.generate(
                            widget.stories.length,
                            (index) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: _buildProgressBar(index),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.grey.shade800,
                              backgroundImage: userAvatar != null && userAvatar.isNotEmpty
                                  ? NetworkImage(userAvatar)
                                  : null,
                              child: userAvatar == null || userAvatar.isEmpty
                                  ? const Icon(Icons.person, color: Colors.white, size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isOwnStory ? 'Your Story' : userName.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    _formatTime(createdAt),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            if (widget.isOwnStory)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white),
                                color: Colors.grey.shade900,
                                onSelected: (value) {
                                  if (value == 'delete') _deleteStory();
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.isOwnStory)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _toggleViewers,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.visibility,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tap to see viewers',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_up,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showViewers)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleViewers,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.8),
                    child: SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Text(
                                  'Story Views',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_viewers.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: _toggleViewers,
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white24, height: 1),
                          Expanded(
                            child: _loadingViewers
                                ? const Center(
                                    child: CircularProgressIndicator(color: Colors.white),
                                  )
                                : _viewers.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.visibility_off,
                                              color: Colors.white.withValues(alpha: 0.5),
                                              size: 48,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'No views yet',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.7),
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _viewers.length,
                                        itemBuilder: (context, index) {
                                          final viewer = _viewers[index];
                                          final viewerProfile = viewer['viewer'] as Map<String, dynamic>? ?? {};
                                          final name = viewerProfile['full_name'] ?? 
                                                      viewerProfile['username'] ?? 
                                                      'Unknown';
                                          final avatar = viewerProfile['avatar_url'] as String?;
                                          final viewedAt = viewer['viewed_at']?.toString() ?? '';

                                          return ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: Colors.grey.shade700,
                                              backgroundImage: avatar != null && avatar.isNotEmpty
                                                  ? NetworkImage(avatar)
                                                  : null,
                                              child: avatar == null || avatar.isEmpty
                                                  ? const Icon(Icons.person, color: Colors.white)
                                                  : null,
                                            ),
                                            title: Text(
                                              name.toString(),
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                            subtitle: Text(
                                              _formatTime(viewedAt),
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.6),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(int index) {
    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, child) {
        double progress;
        if (index < _currentIndex) {
          progress = 1.0;
        } else if (index == _currentIndex) {
          progress = _progressController.value;
        } else {
          progress = 0.0;
        }

        return Container(
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(String dateStr) {
    try {
      if (dateStr.isEmpty) return '';
      // Parse the UTC timestamp and convert to local time for comparison
      DateTime date = DateTime.parse(dateStr);
      // If the date doesn't have timezone info, assume UTC
      if (!dateStr.contains('Z') && !dateStr.contains('+')) {
        date = DateTime.utc(date.year, date.month, date.day, date.hour, date.minute, date.second, date.millisecond, date.microsecond);
      }
      // Convert to local time for display
      final localDate = date.toLocal();
      final now = DateTime.now();
      final diff = now.difference(localDate);

      if (diff.inSeconds < 60) {
        return 'Just now';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return DateFormat('MMM d').format(localDate);
      }
    } catch (e) {
      debugPrint('_formatTime error: $e for dateStr: $dateStr');
      return '';
    }
  }
}
