import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/core/network/qq_video_resolve.dart';
import 'package:super_collection/features/items/reading_media_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// 阅读页内嵌视频：固定高度 + 全屏播放
///
/// B站 CDN 强依赖 Referer；iOS AVPlayer 的 httpHeaders 不可靠，
/// 因此 bilivideo 走 WebView（HTML video + baseUrl=bilibili.com）。
class ItemVideoPlayer extends StatefulWidget {
  const ItemVideoPlayer({
    super.key,
    required this.url,
    this.coverUrl,
    this.pageUrl,
    this.platform,
    this.pageAudio,
    this.height = 220,
    this.onRefreshUrl,
  });

  final String url;
  final String? coverUrl;
  /// 条目源站链接，用作 CDN Referer。
  final String? pageUrl;
  /// 平台 id，小宇宙等播客走 pageAudio 引擎。
  final String? platform;
  /// 阅读页级音频控制器（滚出视口 / 息屏仍可播）。
  final ReadingMediaController? pageAudio;
  final double height;

  /// 直链失效时回调，返回新 URL；阅读页可对接 refresh-video
  final Future<String?> Function()? onRefreshUrl;

  @override
  State<ItemVideoPlayer> createState() => _ItemVideoPlayerState();
}

bool _needsBilibiliWebView(String url) {
  final lower = url.toLowerCase();
  return lower.contains('bilivideo') ||
      lower.contains('bilibili.com') ||
      lower.contains('hdslb.com') ||
      lower.contains('akamaized.net');
}

bool _bilibiliDeadlineExpired(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final raw = uri.queryParameters['deadline'];
  if (raw == null) return false;
  final ts = int.tryParse(raw);
  if (ts == null) return false;
  return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= ts - 60;
}

String _escapeHtmlAttr(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _bilibiliPlayerHtml(String videoUrl) {
  final src = _escapeHtmlAttr(videoUrl);
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
<style>
  html,body{margin:0;padding:0;background:#000;width:100%;height:100%;overflow:hidden;}
  video{width:100%;height:100%;object-fit:contain;background:#000;}
</style>
</head>
<body>
<video id="v" controls playsinline webkit-playsinline preload="metadata" src="$src"></video>
</body>
</html>
''';
}

class _ItemVideoPlayerState extends State<ItemVideoPlayer> {
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _desktopUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  VideoPlayerController? _controller;
  WebViewController? _webController;
  bool _useWeb = false;
  bool _webReady = false;
  bool _initializing = true;
  bool _showControls = true;
  bool _inFullscreen = false;
  bool _refreshing = false;
  String? _error;
  late String _playUrl;
  bool _didAutoRefresh = false;
  bool _didFailRefresh = false;
  bool _resumeWhenVisible = false;
  bool _usePageAudio = false;
  VoidCallback? _audioListener;

  static const _jsPauseIfPlaying = '''
try{
  var v=document.getElementById("v");
  if(!v) 0;
  else if(!v.paused){window.__wasPlaying=1;v.pause();1;}
  else {window.__wasPlaying=0;0;}
}catch(e){0}
''';

  static const _jsResumeIfWasPlaying = '''
try{
  var v=document.getElementById("v");
  if(v&&window.__wasPlaying===1&&v.paused){v.play();}
  window.__wasPlaying=0;
}catch(e){}
''';

  Future<bool> _pauseWebIfPlaying() async {
    final c = _webController;
    if (c == null) return false;
    try {
      final r = await c.runJavaScriptReturningResult(_jsPauseIfPlaying);
      return r == true || r == 1 || r == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _playUrl = widget.url.trim();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ItemVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    // 父组件换了直链：只更新播放地址，勿重置刷新标记以免失败重试死循环
    final next = widget.url.trim();
    if (next.isEmpty || next == _playUrl) return;
    _playUrl = next;
    _disposePlayers();
    _init();
  }

  Future<void> _bootstrap() async {
    // 仅在 deadline 将过期时预刷新；不要每次打开都 refresh，
    // 否则父组件更新 videoUrl 可能触发重建死循环。
    final refresh = widget.onRefreshUrl;
    if (refresh != null &&
        !_didAutoRefresh &&
        _bilibiliDeadlineExpired(_playUrl)) {
      _didAutoRefresh = true;
      setState(() {
        _initializing = true;
        _error = null;
        _refreshing = true;
      });
      try {
        final next = await refresh();
        if (next != null && next.trim().isNotEmpty) {
          _playUrl = next.trim();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
    await _init();
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _error = null;
      _webReady = false;
    });
    final resolved = await QqVideoResolver.resolveIfNeeded(
      _playUrl,
      posterUrl: widget.coverUrl,
      pageUrl: widget.pageUrl,
    );
    if (!mounted) return;
    if (resolved != null && resolved.trim().isNotEmpty) {
      _playUrl = resolved.trim();
    }
    final uri = Uri.tryParse(_playUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() {
        _initializing = false;
        _error = '视频链接无效';
      });
      return;
    }

    if (_needsBilibiliWebView(_playUrl)) {
      await _initWeb();
      return;
    }
    if (widget.pageAudio != null &&
        isAudioOnlyMediaUrl(_playUrl, platform: widget.platform)) {
      await _initPageAudio();
      return;
    }
    await _initNative(uri);
  }

  Future<void> _initPageAudio() async {
    _usePageAudio = true;
    _useWeb = false;
    _disposeNative();
    _webController = null;
    final session = widget.pageAudio!;
    _audioListener ??= () {
      if (!mounted) return;
      setState(() {
        _initializing = session.initializing;
        _error = session.error;
      });
    };
    session.removeListener(_audioListener!);
    session.addListener(_audioListener!);
    setState(() {
      _initializing = true;
      _error = null;
    });
    await session.loadUrl(
      _playUrl,
      headers: mediaHttpHeadersFor(_playUrl, pageUrl: widget.pageUrl),
    );
    if (!mounted) return;
    setState(() {
      _initializing = session.initializing;
      _error = session.error;
    });
  }

  Future<void> _initWeb() async {
    _useWeb = true;
    _disposeNative();
    var finished = false;
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUa)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final u = Uri.tryParse(req.url);
            final scheme = (u?.scheme ?? '').toLowerCase();
            if (scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'about' ||
                scheme == 'blob' ||
                scheme == 'data') {
              // 避免主框架被导航到 mp4 CDN（应仅作 <video> 子资源）
              if (req.isMainFrame &&
                  (req.url.contains('bilivideo.com') ||
                      req.url.toLowerCase().contains('.mp4'))) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (!mounted || finished || _webController != controller) return;
            finished = true;
            setState(() {
              _initializing = false;
              _webReady = true;
            });
          },
          onWebResourceError: (err) {
            debugPrint('[bili-web] resource err ${err.description}');
          },
        ),
      );

    _webController = controller;
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    try {
      await controller.loadHtmlString(
        _bilibiliPlayerHtml(_playUrl),
        baseUrl: mediaRefererOrigin(widget.pageUrl) ??
            'https://www.bilibili.com/',
      );
      // 兜底：部分机型 onPageFinished 不可靠
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted && !finished && _webController == controller) {
        finished = true;
        setState(() {
          _initializing = false;
          _webReady = true;
        });
      }
    } catch (e) {
      debugPrint('[bili-web] load err $e');
      await _onPlayFailed();
    }
  }

  Future<void> _initNative(Uri uri) async {
    _useWeb = false;
    _webController = null;
    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: mediaHttpHeadersFor(_playUrl, pageUrl: widget.pageUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: true,
      ),
    );
    _controller = controller;
    controller.addListener(_onTick);

    try {
      await controller.initialize();
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() => _initializing = false);
    } catch (_) {
      await controller.dispose();
      if (_controller == controller) _controller = null;
      if (!mounted) return;
      await _onPlayFailed();
    }
  }

  Future<void> _onPlayFailed() async {
    if (!_refreshing && !_didFailRefresh) {
      _didFailRefresh = true;
      setState(() => _refreshing = true);
      try {
        final qq = await QqVideoResolver.resolveIfNeeded(
          widget.url,
          posterUrl: widget.coverUrl,
          pageUrl: widget.pageUrl,
          force: true,
        );
        if (qq != null && qq.trim().isNotEmpty && qq.trim() != _playUrl) {
          _playUrl = qq.trim();
          if (!mounted) return;
          setState(() => _refreshing = false);
          await _init();
          return;
        }
        final refresh = widget.onRefreshUrl;
        if (refresh != null) {
          final next = await refresh();
          if (next != null &&
              next.trim().isNotEmpty &&
              next.trim() != _playUrl) {
            _playUrl = next.trim();
            if (!mounted) return;
            setState(() => _refreshing = false);
            await _init();
            return;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _refreshing = false);
    }

    setState(() {
      _initializing = false;
      _error = '无法播放（需防盗链或链接已失效，可点重试刷新）';
    });
  }

  Future<void> _retry() async {
    _didFailRefresh = false;
    setState(() {
      _initializing = true;
      _error = null;
      _refreshing = true;
    });
    try {
      final qq = await QqVideoResolver.resolveIfNeeded(
        widget.url,
        posterUrl: widget.coverUrl,
        pageUrl: widget.pageUrl,
        force: true,
      );
      if (qq != null && qq.trim().isNotEmpty) {
        _playUrl = qq.trim();
      } else {
        final refresh = widget.onRefreshUrl;
        if (refresh != null) {
          final next = await refresh();
          if (next != null && next.trim().isNotEmpty) {
            _playUrl = next.trim();
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _refreshing = false);
    _disposePlayers();
    await _init();
  }

  void _onTick() {
    if (!mounted || _inFullscreen) return;
    setState(() {});
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted || _inFullscreen) return;
    final mostlyHidden = info.visibleFraction <= 0.05;
    if (mostlyHidden) {
      if (_useWeb) {
        if (_webReady) {
          unawaited(() async {
            final wasPlaying = await _pauseWebIfPlaying();
            if (mounted && wasPlaying) {
              _resumeWhenVisible = true;
            }
          }());
        }
      } else {
        final c = _controller;
        if (c != null && c.value.isInitialized && c.value.isPlaying) {
          _resumeWhenVisible = true;
          // 滚出视口时系统常会暂停 Platform View；对音频尽量续播
          unawaited(c.play());
        }
      }
      return;
    }
    if (!_resumeWhenVisible) return;
    _resumeWhenVisible = false;
    unawaited(_resumePlayback());
  }

  Future<void> _resumePlayback() async {
    if (_useWeb) {
      await _webController?.runJavaScript(_jsResumeIfWasPlaying);
      return;
    }
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) {
      await c.play();
    }
  }

  Widget _wrapWithVisibility(Widget child) {
    return VisibilityDetector(
      key: ValueKey('video-vis-${widget.url}-${identityHashCode(this)}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: child,
    );
  }

  void _disposeNative() {
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    c?.dispose();
  }

  void _disposePlayers() {
    _disposeNative();
    _webController = null;
    _webReady = false;
    _useWeb = false;
  }

  @override
  void deactivate() {
    if (_useWeb && _webReady && !_inFullscreen) {
      unawaited(() async {
        final wasPlaying = await _pauseWebIfPlaying();
        if (wasPlaying) _resumeWhenVisible = true;
      }());
    }
    super.deactivate();
  }

  @override
  void dispose() {
    if (_usePageAudio && _audioListener != null) {
      widget.pageAudio?.removeListener(_audioListener!);
    } else {
      _disposePlayers();
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_usePageAudio) {
      await widget.pageAudio?.togglePlay();
      return;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  Future<void> _enterFullscreenNative() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _inFullscreen) return;
    setState(() => _inFullscreen = true);
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullscreenVideoPage(controller: c);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (!mounted) return;
    setState(() => _inFullscreen = false);
  }

  Future<void> _enterFullscreenWeb() async {
    if (_webController == null || _inFullscreen) return;
    setState(() => _inFullscreen = true);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenWebVideoPage(
          playUrl: _playUrl,
          pageUrl: widget.pageUrl,
          userAgent: _desktopUa,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _inFullscreen = false);
    // 全屏页独立 WebView，返回后重建内嵌播放器
    await _initWeb();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _wrapWithVisibility(
        Container(
          width: double.infinity,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: _muted, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 14, color: _muted),
                ),
              ),
              TextButton(
                onPressed: _retry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_useWeb) {
      return _wrapWithVisibility(_buildWebShell());
    }
    if (_usePageAudio) {
      return _buildAudioShell();
    }
    return _wrapWithVisibility(_buildNativeShell());
  }

  Widget _buildAudioShell() {
    final session = widget.pageAudio;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final cover = widget.coverUrl?.trim() ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (cover.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    cover,
                    fit: BoxFit.cover,
                    headers: mediaHttpHeadersFor(cover, pageUrl: widget.pageUrl),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if (cover.isNotEmpty)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              if (_initializing)
                const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                )
              else if (_error == null) ...[
                GestureDetector(
                  onTap: () => setState(() => _showControls = !_showControls),
                  child: const SizedBox.expand(),
                ),
                if (_showControls || !session.isPlaying)
                  GestureDetector(
                    onTap: _togglePlay,
                    child: _RoundPlayButton(playing: session.isPlaying),
                  ),
                if (_showControls)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _AudioBottomBar(
                      session: session,
                      accent: _blue,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebShell() {
    final web = _webController;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: Stack(
            children: [
              if (web != null && !_inFullscreen)
                Positioned.fill(child: WebViewWidget(controller: web)),
              if (_initializing || _refreshing)
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              if (_webReady && !_initializing)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    child: IconButton(
                      tooltip: '全屏',
                      onPressed: _enterFullscreenWeb,
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNativeShell() {
    final c = _controller;
    final ready = !_inFullscreen && c != null && c.value.isInitialized;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (ready)
                GestureDetector(
                  onTap: () => setState(() => _showControls = !_showControls),
                  onDoubleTap: _enterFullscreenNative,
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: c.value.size.width,
                        height: c.value.size.height,
                        child: VideoPlayer(c),
                      ),
                    ),
                  ),
                )
              else if (widget.coverUrl != null &&
                  widget.coverUrl!.trim().isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    widget.coverUrl!.trim(),
                    fit: BoxFit.cover,
                    headers: mediaHttpHeadersFor(
                      widget.coverUrl!.trim(),
                      pageUrl: widget.pageUrl,
                    ),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if (_initializing)
                const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              if (ready && _showControls) ...[
                GestureDetector(
                  onTap: _togglePlay,
                  child: _RoundPlayButton(playing: c.value.isPlaying),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _VideoBottomBar(
                    controller: c,
                    accent: _blue,
                    onFullscreen: _enterFullscreenNative,
                    fullscreen: false,
                  ),
                ),
              ],
              if (ready && !_showControls && !c.value.isPlaying)
                GestureDetector(
                  onTap: () {
                    setState(() => _showControls = true);
                    _togglePlay();
                  },
                  child: const _RoundPlayButton(playing: false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenWebVideoPage extends StatefulWidget {
  const _FullscreenWebVideoPage({
    required this.playUrl,
    this.pageUrl,
    required this.userAgent,
  });

  final String playUrl;
  final String? pageUrl;
  final String userAgent;

  @override
  State<_FullscreenWebVideoPage> createState() =>
      _FullscreenWebVideoPageState();
}

class _FullscreenWebVideoPageState extends State<_FullscreenWebVideoPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.userAgent)
      ..setBackgroundColor(Colors.black)
      ..loadHtmlString(
        _bilibiliPlayerHtml(widget.playUrl),
        baseUrl: mediaRefererOrigin(widget.pageUrl) ??
            'https://www.bilibili.com/',
      );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: '退出全屏',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  static const _blue = Color(0xFF2F6FED);

  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePlay() async {
    final c = widget.controller;
    if (!c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  void _exit() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ready = c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (ready)
              GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                child: Center(
                  child: AspectRatio(
                    aspectRatio:
                        c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
                    child: VideoPlayer(c),
                  ),
                ),
              )
            else
              const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            if (ready && _showControls) ...[
              GestureDetector(
                onTap: _togglePlay,
                child: _RoundPlayButton(playing: c.value.isPlaying, size: 64),
              ),
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  onPressed: _exit,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: '退出全屏',
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _VideoBottomBar(
                  controller: c,
                  accent: _blue,
                  onFullscreen: _exit,
                  fullscreen: true,
                ),
              ),
            ],
            if (ready && !_showControls && !c.value.isPlaying)
              GestureDetector(
                onTap: () {
                  setState(() => _showControls = true);
                  _togglePlay();
                },
                child: const _RoundPlayButton(playing: false, size: 64),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundPlayButton extends StatelessWidget {
  const _RoundPlayButton({required this.playing, this.size = 56});

  final bool playing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: Colors.white,
        size: size * 0.64,
      ),
    );
  }
}

class _VideoBottomBar extends StatelessWidget {
  const _VideoBottomBar({
    required this.controller,
    required this.accent,
    required this.onFullscreen,
    required this.fullscreen,
  });

  final VideoPlayerController controller;
  final Color accent;
  final VoidCallback onFullscreen;
  final bool fullscreen;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 20, 4, fullscreen ? 12 : 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.65),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.only(bottom: 4),
            colors: VideoProgressColors(
              playedColor: accent,
              bufferedColor: const Color(0x66FFFFFF),
              backgroundColor: const Color(0x33FFFFFF),
            ),
          ),
          Row(
            children: [
              Text(
                '${_fmt(v.position)} / ${_fmt(v.duration)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onFullscreen,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: fullscreen ? '退出全屏' : '全屏',
                icon: Icon(
                  fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudioBottomBar extends StatelessWidget {
  const _AudioBottomBar({
    required this.session,
    required this.accent,
  });

  final ReadingMediaController session;
  final Color accent;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = session.duration ?? Duration.zero;
    final pos = session.position;
    final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
    final value = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.65),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value,
              max: maxMs,
              activeColor: accent,
              inactiveColor: const Color(0x33FFFFFF),
              onChanged: total.inMilliseconds <= 0
                  ? null
                  : (v) => session.seek(Duration(milliseconds: v.round())),
            ),
          ),
          Row(
            children: [
              Text(
                '${_fmt(pos)} / ${_fmt(total)}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
