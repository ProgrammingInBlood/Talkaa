import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'watch_party_page.dart';

class WatchPartyWebViewPage extends StatefulWidget {
  final StreamingService service;
  final void Function(String url, String title)? onVideoSelected;
  
  const WatchPartyWebViewPage({super.key, required this.service, this.onVideoSelected});

  @override
  State<WatchPartyWebViewPage> createState() => _WatchPartyWebViewPageState();
}

class _WatchPartyWebViewPageState extends State<WatchPartyWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;
  
  @override
  void initState() {
    super.initState();
    _initWebView();
  }
  
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _loadingProgress = progress / 100;
              if (progress == 100) {
                _isLoading = false;
              }
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _injectPlaybackControls();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.service.url));
  }
  
  Future<void> _injectPlaybackControls() async {
    // Inject JavaScript to communicate video state
    // This is a basic implementation - full sync would need WebSocket/Realtime
    await _controller.runJavaScript('''
      (function() {
        // Find video elements and attach listeners
        const videos = document.querySelectorAll('video');
        videos.forEach(video => {
          video.addEventListener('play', () => {
            console.log('Video playing');
          });
          video.addEventListener('pause', () => {
            console.log('Video paused');
          });
          video.addEventListener('seeked', () => {
            console.log('Video seeked to: ' + video.currentTime);
          });
        });
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: widget.service.color.withValues(alpha: 0.9),
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.service.icon, size: 20),
            const SizedBox(width: 8),
            Text(widget.service.name),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.reload(),
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'home':
                  _controller.loadRequest(Uri.parse(widget.service.url));
                  break;
                case 'share':
                  _showShareDialog();
                  break;
                case 'controls':
                  _showControlsSheet();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'home',
                child: Row(
                  children: [
                    Icon(Icons.home_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Go to Home'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'controls',
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Playback Controls'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Share Party'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          // Bottom control bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Party status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Solo Mode',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Control buttons
                  _buildControlButton(
                    icon: Icons.skip_previous_rounded,
                    onTap: () => _seekVideo(-10),
                    tooltip: 'Back 10s',
                  ),
                  const SizedBox(width: 8),
                  _buildControlButton(
                    icon: Icons.play_arrow_rounded,
                    onTap: _togglePlayPause,
                    tooltip: 'Play/Pause',
                    isPrimary: true,
                  ),
                  const SizedBox(width: 8),
                  _buildControlButton(
                    icon: Icons.skip_next_rounded,
                    onTap: () => _seekVideo(10),
                    tooltip: 'Forward 10s',
                  ),
                  const SizedBox(width: 16),
                  _buildControlButton(
                    icon: Icons.people_rounded,
                    onTap: _showShareDialog,
                    tooltip: 'Invite Friends',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool isPrimary = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isPrimary ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: isPrimary ? cs.onPrimary : cs.onSurface,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _togglePlayPause() async {
    await _controller.runJavaScript('''
      (function() {
        const video = document.querySelector('video');
        if (video) {
          if (video.paused) {
            video.play();
          } else {
            video.pause();
          }
        }
      })();
    ''');
  }
  
  Future<void> _seekVideo(int seconds) async {
    await _controller.runJavaScript('''
      (function() {
        const video = document.querySelector('video');
        if (video) {
          video.currentTime += $seconds;
        }
      })();
    ''');
  }
  
  void _showShareDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('Invite Friends'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_add_rounded,
              size: 64,
              color: cs.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Party sync is coming soon!',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Soon you\'ll be able to watch together with friends in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
  
  void _showControlsSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Playback Controls',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLargeControlButton(
                    icon: Icons.replay_10_rounded,
                    label: '-10s',
                    onTap: () {
                      _seekVideo(-10);
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildLargeControlButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Play/Pause',
                    onTap: () {
                      _togglePlayPause();
                      Navigator.pop(ctx);
                    },
                    isPrimary: true,
                  ),
                  _buildLargeControlButton(
                    icon: Icons.forward_10_rounded,
                    label: '+10s',
                    onTap: () {
                      _seekVideo(10);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLargeControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isPrimary ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: isPrimary ? cs.onPrimary : cs.onSurface,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
