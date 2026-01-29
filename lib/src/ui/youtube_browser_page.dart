import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'youtube_player_page.dart';

class YouTubeBrowserPage extends StatefulWidget {
  final void Function(String url, String title)? onVideoSelected;
  
  const YouTubeBrowserPage({super.key, this.onVideoSelected});

  @override
  State<YouTubeBrowserPage> createState() => _YouTubeBrowserPageState();
}

class _YouTubeBrowserPageState extends State<YouTubeBrowserPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentUrl = 'https://m.youtube.com';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'VideoInterceptor',
        onMessageReceived: (JavaScriptMessage message) {
          final videoUrl = message.message;
          debugPrint('YouTubeBrowser: Intercepted video URL: $videoUrl');
          if (videoUrl.isNotEmpty && _isYouTubeVideoUrl(videoUrl)) {
            _openInNativePlayer(videoUrl);
          }
        },
      )
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
              _currentUrl = url;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _injectVideoInterceptor();
            
            // Check if we landed on a video page
            if (_isYouTubeVideoUrl(url)) {
              _openInNativePlayer(url);
              // Go back to browse page
              _controller.loadRequest(Uri.parse('https://m.youtube.com'));
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            debugPrint('YouTubeBrowser: Navigation to: $url');
            
            // Check if this is a YouTube video URL
            if (_isYouTubeVideoUrl(url)) {
              // Open in native player instead
              _openInNativePlayer(url);
              return NavigationDecision.prevent;
            }
            
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
          onUrlChange: (UrlChange change) {
            final url = change.url;
            if (url != null) {
              debugPrint('YouTubeBrowser: URL changed to: $url');
              setState(() => _currentUrl = url);
              if (_isYouTubeVideoUrl(url)) {
                _openInNativePlayer(url);
                // Navigate back
                _controller.loadRequest(Uri.parse('https://m.youtube.com'));
              }
            }
          },
        ),
      )
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36')
      ..loadRequest(Uri.parse('https://m.youtube.com'));
  }
  
  void _injectVideoInterceptor() {
    _controller.runJavaScript('''
      (function() {
        // Intercept clicks on video links
        document.addEventListener('click', function(e) {
          var target = e.target;
          // Walk up the DOM tree to find anchor tags
          while (target && target.tagName !== 'A') {
            target = target.parentElement;
          }
          if (target && target.href) {
            var href = target.href;
            // Check if it's a video link
            if (href.includes('/watch?v=') || href.includes('/shorts/') || href.includes('youtu.be/')) {
              e.preventDefault();
              e.stopPropagation();
              VideoInterceptor.postMessage(href);
              return false;
            }
          }
        }, true);
        
        // Also intercept programmatic navigation
        var originalPushState = history.pushState;
        history.pushState = function() {
          originalPushState.apply(this, arguments);
          var url = arguments[2];
          if (url && (url.includes('/watch?v=') || url.includes('/shorts/'))) {
            VideoInterceptor.postMessage(window.location.origin + url);
          }
        };
      })();
    ''');
  }

  bool _isYouTubeVideoUrl(String url) {
    // Match various YouTube video URL formats
    final patterns = [
      RegExp(r'youtube\.com/watch\?v='),
      RegExp(r'youtube\.com/shorts/'),
      RegExp(r'youtu\.be/'),
      RegExp(r'm\.youtube\.com/watch\?v='),
    ];
    
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  Future<void> _openInNativePlayer(String url) async {
    if (widget.onVideoSelected != null) {
      // Get video title first
      String title = 'YouTube Video';
      try {
        final yt = YoutubeExplode();
        final videoId = VideoId.parseVideoId(url);
        if (videoId != null) {
          final video = await yt.videos.get(videoId);
          title = video.title;
        }
        yt.close();
      } catch (e) {
        debugPrint('Error getting video title: $e');
      }
      
      // Call callback - the parent will handle navigation
      // Don't pop here as the parent's pushAndRemoveUntil will clear the stack
      widget.onVideoSelected!(url, title);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => YouTubePlayerPage(videoUrl: url),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('YouTube'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.home_rounded),
            onPressed: () => _controller.loadRequest(Uri.parse('https://m.youtube.com')),
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: cs.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap on any video to play in native player',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // WebView
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
