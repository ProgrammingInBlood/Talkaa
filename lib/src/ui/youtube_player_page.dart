import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_video_player/omni_video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubePlayerPage extends StatefulWidget {
  final String? videoUrl;
  final void Function(String url, String title)? onVideoSelected;
  
  const YouTubePlayerPage({super.key, this.videoUrl, this.onVideoSelected});

  @override
  State<YouTubePlayerPage> createState() => _YouTubePlayerPageState();
}

class _YouTubePlayerPageState extends State<YouTubePlayerPage> {
  final _urlController = TextEditingController();
  
  OmniPlaybackController? _playerController;
  String? _currentVideoUrl;
  
  bool _isLoading = false;
  String? _error;
  String? _videoTitle;
  String? _channelName;
  
  @override
  void initState() {
    super.initState();
    if (widget.videoUrl != null) {
      _urlController.text = widget.videoUrl!;
      _loadVideo(widget.videoUrl!);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _playerController?.removeListener(_onPlayerUpdate);
    super.dispose();
  }
  
  void _onControllerCreated(OmniPlaybackController controller) {
    _playerController?.removeListener(_onPlayerUpdate);
    _playerController = controller..addListener(_onPlayerUpdate);
  }
  
  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadVideo(String url) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final videoId = VideoId.parseVideoId(url);
      if (videoId == null) {
        throw Exception('Invalid YouTube URL');
      }

      // Get video metadata
      final yt = YoutubeExplode();
      final video = await yt.videos.get(videoId);
      yt.close();
      
      setState(() {
        _videoTitle = video.title;
        _channelName = video.author;
        _currentVideoUrl = url;
        _isLoading = false;
      });
      
      // If onVideoSelected callback exists and video loaded, call it
      if (widget.onVideoSelected != null && _videoTitle != null) {
        widget.onVideoSelected!(url, _videoTitle!);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
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
        title: Text(
          _videoTitle ?? 'YouTube Player',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          // Video Player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildVideoPlayer(cs),
          ),
          
          // Video Info & Search
          Expanded(
            child: Container(
              color: cs.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // URL Input
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText: 'Paste YouTube URL here...',
                        prefixIcon: const Icon(Icons.link),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: _isLoading 
                              ? null 
                              : () => _loadVideo(_urlController.text.trim()),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      onSubmitted: (url) => _loadVideo(url.trim()),
                    ),
                    const SizedBox(height: 16),
                    
                    // Paste from clipboard button
                    OutlinedButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _urlController.text = data!.text!;
                          _loadVideo(data.text!.trim());
                        }
                      },
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Paste from clipboard'),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Video details
                    if (_videoTitle != null) ...[
                      Text(
                        _videoTitle!,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_channelName != null)
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              _channelName!,
                              style: TextStyle(
                                fontSize: 14,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: cs.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'How to use',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '1. Copy a YouTube video URL\n'
                            '2. Paste it above or use the paste button\n'
                            '3. Press play to start watching',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(ColorScheme cs) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Loading video...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Error loading video',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadVideo(_urlController.text.trim()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentVideoUrl != null) {
      return OmniVideoPlayer(
        key: ValueKey(_currentVideoUrl),
        callbacks: VideoPlayerCallbacks(
          onControllerCreated: _onControllerCreated,
          onFullScreenToggled: (isFullScreen) {},
          onFinished: () {},
        ),
        configuration: VideoPlayerConfiguration(
          videoSourceConfiguration: VideoSourceConfiguration.youtube(
            videoUrl: Uri.parse(_currentVideoUrl!),
            preferredQualities: [
              OmniVideoQuality.high1080,
              OmniVideoQuality.high720,
              OmniVideoQuality.medium480,
            ],
            availableQualities: [
              OmniVideoQuality.high1080,
              OmniVideoQuality.high720,
              OmniVideoQuality.medium480,
              OmniVideoQuality.medium360,
              OmniVideoQuality.low144,
            ],
            enableYoutubeWebViewFallback: true,
            forceYoutubeWebViewOnly: false,
          ).copyWith(
            autoPlay: true,
            initialVolume: 1.0,
            allowSeeking: true,
          ),
          playerUIVisibilityOptions: PlayerUIVisibilityOptions().copyWith(
            showSeekBar: true,
            showCurrentTime: true,
            showDurationTime: true,
            showLoadingWidget: true,
            showErrorPlaceholder: true,
            showFullScreenButton: true,
            showSwitchVideoQuality: true,
            showPlaybackSpeedButton: true,
            showMuteUnMuteButton: true,
            showPlayPauseReplayButton: true,
            enableForwardGesture: true,
            enableBackwardGesture: true,
          ),
          playerTheme: OmniVideoPlayerThemeData().copyWith(
            overlays: VideoPlayerOverlayTheme().copyWith(
              backgroundColor: Colors.black,
              alpha: 50,
            ),
          ),
          customPlayerWidgets: CustomPlayerWidgets().copyWith(
            loadingWidget: const CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    // Empty state
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 64,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Paste a YouTube URL to start',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
