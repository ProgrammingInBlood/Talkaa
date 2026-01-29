import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../watch_party/watch_party_service.dart';

class InstagramReelsRoom extends ConsumerStatefulWidget {
  final WatchPartyRoom room;
  final bool isHost;

  const InstagramReelsRoom({
    super.key,
    required this.room,
    required this.isHost,
  });

  @override
  ConsumerState<InstagramReelsRoom> createState() => _InstagramReelsRoomState();
}

class _InstagramReelsRoomState extends ConsumerState<InstagramReelsRoom> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentUrl = '';
  StreamSubscription? _roomSubscription;
  StreamSubscription? _activitySubscription;
  StreamSubscription? _participantCountSubscription;
  List<ParticipantActivity> _recentActivity = [];
  late WatchPartyRoom _room;
  bool _isSyncing = false;
  String? _lastSyncedUrl;
  int _participantCount = 0;
  bool _isLoggedIn = false;
  static const Duration _autoplayCooldown = Duration(milliseconds: 1200);
  DateTime? _lastAutoplayAttempt;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _currentUrl = widget.room.videoUrl;
    _enableWakeLock();
    _initWebView();
    _subscribeToRoom();
    _subscribeToParticipantCount();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _joinRoom();
      await _loadRecentActivity();
      _subscribeToActivity();
    });
  }

  @override
  void dispose() {
    _disableWakeLock();
    _roomSubscription?.cancel();
    _activitySubscription?.cancel();
    _participantCountSubscription?.cancel();
    super.dispose();
  }

  Future<void> _enableWakeLock() async {
    try {
      await WakelockPlus.enable();
      debugPrint('InstagramReels: Wake lock enabled');
    } catch (e) {
      debugPrint('InstagramReels: Failed to enable wake lock: $e');
    }
  }

  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      debugPrint('InstagramReels: Wake lock disabled');
    } catch (e) {
      debugPrint('InstagramReels: Failed to disable wake lock: $e');
    }
  }

  void _initWebView() {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..addJavaScriptChannel(
        'ReelInterceptor',
        onMessageReceived: (JavaScriptMessage message) {
          _onReelCodeReceived(message.message);
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
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            _checkLoginStatus();
            _maybeSyncReel(url);
            // Inject JavaScript to hide non-reel UI elements and detect reel changes
            if (_isLoggedIn) {
              _injectReelsOnlyMode();
              // Trigger autoplay for host on initial load
              if (widget.isHost) {
                _triggerAutoplay();
              }
            }
            if (widget.isHost && _isLoggedIn) {
              _injectReelInterceptor();
            }
          },
          onUrlChange: (UrlChange change) {
            final url = change.url;
            if (url != null) {
              _handleUrlChange(url);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            return _handleNavigation(request.url);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      );

    if (_controller.platform is AndroidWebViewController) {
      final androidController =
          _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    _controller.loadRequest(
      Uri.parse(_currentUrl.isNotEmpty ? _currentUrl : 'https://www.instagram.com/reels/'),
    );
  }

  NavigationDecision _handleNavigation(String url) {
    final lowerUrl = url.toLowerCase();
    
    // If not logged in, allow all navigation (for login flow)
    if (!_isLoggedIn) {
      debugPrint('InstagramReels: Allowing navigation (not logged in): $url');
      return NavigationDecision.navigate;
    }
    
    // Once logged in, enforce reels-only restriction
    
    // Allow reels URLs
    if (_isReelUrl(lowerUrl)) {
      return NavigationDecision.navigate;
    }
    
    // Allow authentication/API URLs
    if (_isAuthUrl(lowerUrl)) {
      return NavigationDecision.navigate;
    }
    
    // Block navigation to non-reel content (but don't show snackbar for resource requests)
    if (!url.contains('/static/') && 
        !url.contains('/graphql/') && 
        !url.contains('/ajax/') &&
        !url.contains('.js') &&
        !url.contains('.css') &&
        !url.contains('.png') &&
        !url.contains('.jpg')) {
      debugPrint('InstagramReels: Blocking navigation to: $url');
      _showBlockedSnackbar();
    }
    return NavigationDecision.prevent;
  }

  Future<void> _checkLoginStatus() async {
    try {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie'
      ) as String;
      
      // Check if user is logged in by looking for session cookies
      final wasLoggedIn = _isLoggedIn;
      _isLoggedIn = cookies.contains('sessionid') || cookies.contains('ds_user_id');
      
      if (!wasLoggedIn && _isLoggedIn) {
        debugPrint('InstagramReels: User logged in, redirecting to reels');
        // User just logged in, redirect to reels
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isReelUrl(_currentUrl) == false) {
            _controller.loadRequest(Uri.parse('https://www.instagram.com/reels/'));
          }
        });
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('InstagramReels: Error checking login status: $e');
    }
  }

  bool _isAuthUrl(String url) {
    return url.contains('instagram.com/accounts/') ||
           url.contains('instagram.com/challenge') ||
           url.contains('facebook.com/login') ||
           url.contains('facebook.com/v') ||
           url.contains('accounts.google.com') ||
           url.contains('instagram.com/api/') ||
           url.contains('instagram.com/oauth') ||
           url.contains('instagram.com/login') ||
           url.contains('instagram.com/data/') ||
           url.contains('instagram.com/graphql/') ||
           url.contains('instagram.com/ajax/') ||
           url.contains('instagram.com/web/') ||
           url.contains('instagram.com/static/');
  }

  bool _isReelUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('instagram.com/reels') ||
           lowerUrl.contains('instagram.com/reel/');
  }

  void _handleUrlChange(String url) {
    if (_currentUrl != url && mounted) {
      setState(() => _currentUrl = url);
    }
    _maybeSyncReel(url);
  }

  void _maybeSyncReel(String url) {
    if (!widget.isHost || _isSyncing) return;
    if (!_isReelUrl(url)) return;
    if (_room.videoUrl == url || _lastSyncedUrl == url) return;
    _syncReelToParticipants(url);
  }

  void _onReelCodeReceived(String reelCode) {
    if (!widget.isHost || reelCode.isEmpty) return;
    final reelUrl = 'https://www.instagram.com/reel/$reelCode/';
    debugPrint('InstagramReels: Detected reel code: $reelCode -> $reelUrl');
    if (_lastSyncedUrl != reelUrl) {
      _syncReelToParticipants(reelUrl);
      // Trigger autoplay for host when they change reels
      Future.delayed(const Duration(milliseconds: 300), () {
        _triggerAutoplay();
      });
    }
  }

  Future<void> _injectReelInterceptor() async {
    // Intercept GraphQL responses to detect reel changes
    await _controller.runJavaScript('''
      (function() {
        if (window._reelInterceptorInstalled) return;
        window._reelInterceptorInstalled = true;
        
        let lastReelCode = null;
        let isInitialLoad = true;
        
        // Prevent share button clicks during initial load
        setTimeout(() => {
          isInitialLoad = false;
        }, 2000);
        
        // Intercept fetch to catch GraphQL responses
        const originalFetch = window.fetch;
        window.fetch = async function(...args) {
          const response = await originalFetch.apply(this, args);
          const url = args[0];
          
          if (url && url.toString().includes('/graphql/query')) {
            try {
              const clone = response.clone();
              const json = await clone.json();
              
              // Look for reel code in the response
              if (json?.data?.fetch__XDTMediaDict?.code) {
                const code = json.data.fetch__XDTMediaDict.code;
                if (code !== lastReelCode) {
                  lastReelCode = code;
                  ReelInterceptor.postMessage(code);
                }
              }
            } catch (e) {}
          }
          return response;
        };
        
        function triggerShareForReelCode() {
          if (isInitialLoad) return;
          
          const shareBtn = document.querySelector('svg[aria-label="Share"]')?.closest('[role="button"]');
          if (shareBtn) {
            shareBtn.click();
            // Close the share dialog immediately
            setTimeout(() => {
              const closeBtn = document.querySelector('[aria-label="Close"]');
              if (closeBtn) closeBtn.click();
              // Also try pressing Escape
              document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', keyCode: 27 }));
            }, 50);
          }
        }
        
        // Detect scroll on the main element (primary method)
        let lastScrollTop = 0;
        let scrollTimeout = null;
        
        document.addEventListener('scroll', () => {
          if (isInitialLoad) return;
          
          const currentScroll = window.scrollY || document.documentElement.scrollTop;
          if (Math.abs(currentScroll - lastScrollTop) > 100) {
            lastScrollTop = currentScroll;
            clearTimeout(scrollTimeout);
            scrollTimeout = setTimeout(() => {
              triggerShareForReelCode();
            }, 500);
          }
        }, true);
        
        // Observe reel container changes (secondary method, delayed start)
        setTimeout(() => {
          const reelsContainer = document.querySelector('section main > div > div');
          if (reelsContainer) {
            let mutationTimeout = null;
            const observer = new MutationObserver(() => {
              if (isInitialLoad) return;
              
              clearTimeout(mutationTimeout);
              mutationTimeout = setTimeout(() => {
                triggerShareForReelCode();
              }, 500);
            });
            
            observer.observe(reelsContainer, { childList: true, subtree: false });
          }
        }, 3000);
      })();
    ''');
  }

  Future<void> _injectReelsOnlyMode() async {
    // Hide navigation elements that lead to non-reel pages
    await _controller.runJavaScript('''
      (function() {
        const bottomNavSelector = '#mount_0_0_yO > div > div > div.x9f619'
          + '.x1n2onr6.x1ja2u2z > div > div > div.x78zum5'
          + '.xdt5ytf.x1t2pt76.x1n2onr6.x1ja2u2z.x10cihs4'
          + ' > div.html-div.xdj266r.x14z9mp.xat24cr.x1lziwak'
          + '.xexx8yu.xyri2b.x18d9i69.x1c1uobl.x9f619.x16ye13r'
          + '.xvbhtw8.x78zum5.x15mokao.x1ga7v0g.x16uus16.xbiv7yw'
          + '.x1uhb9sk.x1plvlek.xryxfnj.x1c4vz4f.x2lah0s.xdt5ytf'
          + '.xqjyukv.x1qjc9v5.x1oa3qoh.x1qughib > div.html-div'
          + '.xdj266r.x14z9mp.xat24cr.x1lziwak.xexx8yu.xyri2b.x18d9i69'
          + '.x1c1uobl.x9f619.xjbqb8w.x78zum5.x15mokao.x1ga7v0g.x16uus16'
          + '.xbiv7yw.xixxii4.x1ey2m1c.x1plvlek.xryxfnj.x1c4vz4f.x2lah0s'
          + '.xdt5ytf.xqjyukv.x1qjc9v5.x1oa3qoh.x1nhvcw1.xg7h5cd.xh8yej3'
          + '.xhtitgo.x6w1myc.x1jeouym > div > div';
        const removeBottomNav = () => {
          const bottomNav = document.querySelector(bottomNavSelector);
          if (bottomNav) bottomNav.remove();
          const roleNav = document.querySelector('div[role="navigation"]');
          if (roleNav) roleNav.remove();
        };

        // Hide bottom navigation bar
        removeBottomNav();
        
        // Hide header elements that link to other pages
        const headers = document.querySelectorAll('header a:not([href*="reel"])');
        headers.forEach(el => el.style.pointerEvents = 'none');
        
        // Hide DM icon
        const dmIcons = document.querySelectorAll('a[href*="/direct"]');
        dmIcons.forEach(el => el.style.display = 'none');
        
        // Hide profile links
        const profileLinks = document.querySelectorAll('a[href^="/"]:not([href*="reel"])');
        profileLinks.forEach(el => {
          if (!el.href.includes('reel') && !el.href.includes('accounts')) {
            el.style.pointerEvents = 'none';
          }
        });
        
        // Observe for dynamic content
        const observer = new MutationObserver(() => {
          removeBottomNav();
          const dm = document.querySelectorAll('a[href*="/direct"]');
          dm.forEach(el => el.style.display = 'none');
        });
        
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    ''');
  }

  void _showBlockedSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Only Reels are available in Watch Party'),
        backgroundColor: const Color(0xFFE4405F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _syncReelToParticipants(String reelUrl) async {
    if (!widget.isHost) return;
    if (_lastSyncedUrl == reelUrl) return;
    _lastSyncedUrl = reelUrl;
    if (mounted) {
      setState(() {
        _room = _room.copyWith(
          videoUrl: reelUrl,
          videoTitle: 'Instagram Reel',
        );
        _currentUrl = reelUrl;
      });
    }
    
    final service = ref.read(watchPartyServiceProvider);
    await service.updateRoom(
      roomId: _room.id,
      videoUrl: reelUrl,
      videoTitle: 'Instagram Reel',
    );
  }

  void _subscribeToRoom() {
    final service = ref.read(watchPartyServiceProvider);
    
    _roomSubscription = service.subscribeToRoom(widget.room.id).listen(
      (updatedRoom) {
        if (!mounted) return;
        
        // If not host and the reel URL changed, navigate to it
        if (!widget.isHost && updatedRoom.videoUrl != _currentUrl && _isReelUrl(updatedRoom.videoUrl)) {
          setState(() {
            _isSyncing = true;
            _room = updatedRoom;
          });
          _navigateToReelWithoutReload(updatedRoom.videoUrl);
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _isSyncing = false);
          });
        } else {
          setState(() => _room = updatedRoom);
        }
        
        // Check if room was closed
        if (!updatedRoom.isActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Room has been closed by host')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      onError: (e) => debugPrint('Room subscription error: $e'),
    );
  }

  Future<void> _navigateToReelWithoutReload(String reelUrl) async {
    try {
      // Use pushState to navigate without page reload (preserves audio/video state)
      await _controller.runJavaScript('''
        (function() {
          try {
            // Use Instagram's client-side routing
            window.history.pushState({}, '', '$reelUrl');
            
            // Trigger Instagram's router to handle the URL change
            window.dispatchEvent(new PopStateEvent('popstate'));
            
            // Also try clicking the link if it exists
            setTimeout(() => {
              const reelLink = document.querySelector('a[href="${reelUrl.replaceAll('https://www.instagram.com', '')}"]');
              if (reelLink) {
                reelLink.click();
              } else {
                // Fallback: force navigation by setting location
                window.location.href = '$reelUrl';
              }
            }, 100);
          } catch (e) {
            console.error('Navigation error:', e);
            // Fallback to full reload if JS navigation fails
            window.location.href = '$reelUrl';
          }
        })();
      ''');
      debugPrint('InstagramReels: Navigated to $reelUrl without reload');
      
      // Trigger autoplay for participants after navigation
      Future.delayed(const Duration(milliseconds: 500), () {
        _triggerAutoplay();
      });
    } catch (e) {
      debugPrint('InstagramReels: JS navigation failed, using loadRequest: $e');
      // Fallback to full page load if JavaScript fails
      _controller.loadRequest(Uri.parse(reelUrl));
    }
  }

  Future<void> _triggerAutoplay() async {
    final now = DateTime.now();
    if (_lastAutoplayAttempt != null &&
        now.difference(_lastAutoplayAttempt!) < _autoplayCooldown) {
      debugPrint('InstagramReels: Autoplay skipped (cooldown)');
      return;
    }
    _lastAutoplayAttempt = now;
    try {
      await _controller.runJavaScript('''
        (function() {
          try {
            const log = (...args) => console.log('InstagramReels: Autoplay', ...args);

            const state = window.__reelAutoplayState || {
              lastAttempt: 0,
              lastSuccess: 0,
              lastUnmute: 0,
            };
            window.__reelAutoplayState = state;
            const now = Date.now();
            if (now - state.lastAttempt < 1200) {
              log('Skip autoplay (cooldown)');
              return;
            }
            state.lastAttempt = now;

            const isElementVisible = (element) => {
              if (!element) {
                return false;
              }
              const rect = element.getBoundingClientRect();
              if (rect.width <= 0 || rect.height <= 0) {
                return false;
              }
              if (rect.bottom <= 0 || rect.top >= window.innerHeight) {
                return false;
              }
              const style = window.getComputedStyle(element);
              if (style.visibility === 'hidden' || style.display === 'none') {
                return false;
              }
              return true;
            };

            const dispatchMouseEvent = (target, type, x, y) => {
              const event = new MouseEvent(type, {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: x,
                clientY: y,
                screenX: x,
                screenY: y,
              });
              target.dispatchEvent(event);
            };

            const dispatchPointerEvent = (target, type, x, y) => {
              if (typeof PointerEvent === 'undefined') {
                return;
              }
              const event = new PointerEvent(type, {
                bubbles: true,
                cancelable: true,
                pointerType: 'touch',
                isPrimary: true,
                clientX: x,
                clientY: y,
                screenX: x,
                screenY: y,
              });
              target.dispatchEvent(event);
            };

            const dispatchTouchEvent = (target, type, x, y) => {
              if (typeof TouchEvent === 'undefined' || typeof Touch === 'undefined') {
                return;
              }
              try {
                const touch = new Touch({
                  identifier: Date.now(),
                  target,
                  clientX: x,
                  clientY: y,
                  screenX: x,
                  screenY: y,
                  radiusX: 2,
                  radiusY: 2,
                  rotationAngle: 0,
                  force: 0.5,
                });
                const event = new TouchEvent(type, {
                  bubbles: true,
                  cancelable: true,
                  touches: [touch],
                  targetTouches: [touch],
                  changedTouches: [touch],
                });
                target.dispatchEvent(event);
              } catch (e) {
                log('Touch event failed', e);
              }
            };

            const clickAtCenter = (element) => {
              const rect = element.getBoundingClientRect();
              const x = rect.left + rect.width / 2;
              const y = rect.top + rect.height / 2;
              const target = document.elementFromPoint(x, y) || element;
              log('Click target', target.tagName, target.id || '');
              target.focus();
              dispatchPointerEvent(target, 'pointerdown', x, y);
              dispatchTouchEvent(target, 'touchstart', x, y);
              dispatchMouseEvent(target, 'mousedown', x, y);
              dispatchPointerEvent(target, 'pointerup', x, y);
              dispatchTouchEvent(target, 'touchend', x, y);
              dispatchMouseEvent(target, 'mouseup', x, y);
              dispatchMouseEvent(target, 'click', x, y);
            };

            const tryPlayVideo = () => {
              const videos = Array.from(document.querySelectorAll('video'));
              const videoElement = videos.find(isElementVisible) || videos[0];
              if (!videoElement) {
                log('No video element found');
                return false;
              }
              const tryUnmuteButton = () => {
                const now = Date.now();
                if (now - state.lastUnmute < 1500) {
                  return;
                }
                const audioButton = Array.from(
                  document.querySelectorAll('[role="button"][aria-label]'),
                ).find((element) => {
                  const label = element.getAttribute('aria-label')?.toLowerCase() ?? '';
                  return label.contains('mute') || label.contains('unmute') || label.contains('sound');
                });
                if (!audioButton) {
                  return;
                }
                const label = audioButton.getAttribute('aria-label')?.toLowerCase() ?? '';
                if (label.contains('unmute') || label.contains('turn on') || label.contains('sound')) {
                  audioButton.click();
                  state.lastUnmute = now;
                  log('Clicked audio button to unmute');
                }
              };

              const ensureUnmuted = () => {
                videoElement.muted = false;
                if (typeof videoElement.volume === 'number') {
                  videoElement.volume = 1;
                }
                tryUnmuteButton();
              };

              if (!videoElement.paused) {
                log('Video already playing');
                state.lastSuccess = Date.now();
                ensureUnmuted();
                return true;
              }
              log('Video found', { paused: videoElement.paused, muted: videoElement.muted });
              if (videoElement.paused) {
                const play = () => {
                  ensureUnmuted();
                  const playPromise = videoElement.play();
                  if (playPromise) {
                    playPromise
                      .then(() => log('video.play() succeeded'))
                      .catch(e => {
                        log('video.play() failed', e);
                        videoElement.muted = true;
                        videoElement.play()
                          .then(() => {
                            log('video.play() muted retry succeeded');
                            setTimeout(ensureUnmuted, 400);
                          })
                          .catch(error => log('video.play() muted retry failed', error));
                      });
                  }
                };
                if (videoElement.readyState >= 2) {
                  play();
                } else {
                  videoElement.addEventListener('loadeddata', play, { once: true });
                }
              }
              return true;
            };

            const tryAutoplay = () => {
              log('Attempting autoplay...');
              const overlayElements = Array.from(
                document.querySelectorAll('div[id^="clipsoverlay"][role="button"]'),
              );
              const overlayElement = overlayElements.find(isElementVisible)
                || overlayElements[0];
              if (overlayElement) {
                log('Overlay found', overlayElement.id);
                overlayElement.focus();
                const wasPlaying = !tryPlayVideo();
                if (wasPlaying) {
                  clickAtCenter(overlayElement);
                }
                setTimeout(() => {
                  tryPlayVideo();
                }, 150);
                return true;
              }

              if (tryPlayVideo()) {
                return true;
              }

              const mainContainer = document.querySelector('section main');
              if (mainContainer) {
                log('Main container found');
                clickAtCenter(mainContainer);
                setTimeout(() => {
                  tryPlayVideo();
                }, 150);
                return true;
              }

              log('No autoplay targets found');
              return false;
            };

            if (!tryAutoplay()) {
              setTimeout(() => tryAutoplay(), 500);
              setTimeout(() => tryAutoplay(), 1200);
            }
          } catch (e) {
            console.error('InstagramReels: Autoplay error:', e);
          }
        })();
      ''');
      debugPrint('InstagramReels: Autoplay trigger initiated');
    } catch (e) {
      debugPrint('InstagramReels: Failed to trigger autoplay: $e');
    }
  }

  Future<void> _loadRecentActivity() async {
    final service = ref.read(watchPartyServiceProvider);
    final activities = await service.getRecentActivity(widget.room.id, limit: 20);
    if (!mounted) return;
    setState(() {
      _recentActivity = activities;
    });
  }

  void _subscribeToActivity() {
    final service = ref.read(watchPartyServiceProvider);
    
    _activitySubscription = service.subscribeToActivity(widget.room.id).listen(
      (activities) {
        if (!mounted) return;
        setState(() => _recentActivity = activities);
      },
      onError: (e) => debugPrint('Activity subscription error: $e'),
    );
  }

  void _subscribeToParticipantCount() {
    final service = ref.read(watchPartyServiceProvider);
    
    _participantCountSubscription = service.subscribeToParticipantCount(widget.room.id).listen(
      (count) {
        if (!mounted) return;
        setState(() => _participantCount = count);
      },
      onError: (e) => debugPrint('Participant count subscription error: $e'),
    );
  }

  Future<void> _joinRoom() async {
    final service = ref.read(watchPartyServiceProvider);
    await service.joinRoom(widget.room.id);
  }

  Future<void> _leaveRoom() async {
    final service = ref.read(watchPartyServiceProvider);
    await service.leaveRoom(widget.room.id);
  }

  Color _getActivityColor(String activityType) {
    switch (activityType) {
      case 'joined':
      case 'created':
        return Colors.green;
      case 'left':
        return Colors.red;
      case 'rejoined':
        return Colors.blue;
      default:
        return Colors.white70;
    }
  }

  IconData _getActivityIcon(String activityType) {
    switch (activityType) {
      case 'joined':
      case 'created':
        return Icons.login_rounded;
      case 'left':
        return Icons.logout_rounded;
      case 'rejoined':
        return Icons.refresh_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Widget _buildToolbarButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontal = (screenWidth * 0.03).clamp(8.0, 12.0).toDouble();
    final vertical = (screenWidth * 0.012).clamp(4.0, 6.0).toDouble();
    final fontSize = (screenWidth * 0.028).clamp(10.0, 12.0).toDouble();
    final iconSize = (screenWidth * 0.032).clamp(14.0, 16.0).toDouble();
    final radius = (screenWidth * 0.05).clamp(14.0, 18.0).toDouble();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveRoom();
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: const Color(0xFFE4405F),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _leaveRoom();
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_collection_rounded, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Instagram Reels', style: TextStyle(fontSize: 16)),
                  Text(
                    widget.isHost ? 'You control the reels' : 'Following host',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _controller.reload(),
              tooltip: 'Refresh',
            ),
            if (widget.isHost)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _closeRoom,
                tooltip: 'Close Room',
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
            // Sync status banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.isHost
                      ? [const Color(0xFF833AB4), const Color(0xFFE1306C)]
                      : [const Color(0xFF405DE6), const Color(0xFF5851DB)],
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isHost ? Icons.swap_vert : Icons.sync,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isHost
                          ? 'Swipe to change reels for everyone'
                          : _isSyncing ? 'Syncing to host...' : 'Synced with host',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '$_participantCount',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // WebView with bottom toolbar overlay
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  // Bottom toolbar overlay (hides Instagram nav)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              // Activity indicator
                              Expanded(
                                child: _recentActivity.isEmpty
                                    ? Row(
                                        children: [
                                          Icon(Icons.history_rounded, size: 16, color: Colors.white38),
                                          const SizedBox(width: 8),
                                          Text(
                                            'No activity',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white38,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      )
                                    : ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _recentActivity.take(3).length,
                                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                                        itemBuilder: (context, index) {
                                          final activity = _recentActivity[index];
                                          final color = _getActivityColor(activity.activityType);
                                          final screenWidth =
                                            MediaQuery.of(context).size.width;
                                          final chipHorizontal =
                                              (screenWidth * 0.025)
                                                  .clamp(8.0, 12.0)
                                                  .toDouble();
                                          final chipVertical =
                                              (screenWidth * 0.012)
                                                  .clamp(4.0, 6.0)
                                                  .toDouble();
                                          final chipFontSize =
                                              (screenWidth * 0.026)
                                                  .clamp(10.0, 12.0)
                                                  .toDouble();
                                          final chipIconSize =
                                              (screenWidth * 0.03)
                                                  .clamp(12.0, 14.0)
                                                  .toDouble();
                                          final chipRadius =
                                              (screenWidth * 0.04)
                                                  .clamp(12.0, 14.0)
                                                  .toDouble();
                                          return Center(
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: chipHorizontal,
                                                vertical: chipVertical,
                                              ),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(chipRadius),
                                                border: Border.all(
                                                  color: color.withValues(alpha: 0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _getActivityIcon(activity.activityType),
                                                    size: chipIconSize,
                                                    color: color,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      activity.userName ?? 'User',
                                                      style: TextStyle(
                                                        fontSize: chipFontSize,
                                                        color: color,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(width: 12),
                              // Action button
                              _buildToolbarButton(
                                context: context,
                                icon: widget.isHost ? Icons.close_rounded : Icons.exit_to_app_rounded,
                                label: widget.isHost ? 'Close' : 'Leave',
                                color: widget.isHost ? Colors.red : Colors.orange,
                                onTap: widget.isHost 
                                    ? _closeRoom
                                    : () async {
                                        await _leaveRoom();
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                        }
                                      },
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
          ],
        ),
      ),
    );
  }

  Future<void> _closeRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Room?'),
        content: const Text('This will end the watch party for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final service = ref.read(watchPartyServiceProvider);
      await service.closeRoom(_room.id);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }
}
