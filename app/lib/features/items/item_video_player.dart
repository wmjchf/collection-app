import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// 阅读页内嵌视频：固定高度 + 全屏播放
class ItemVideoPlayer extends StatefulWidget {
  const ItemVideoPlayer({
    super.key,
    required this.url,
    this.coverUrl,
    this.height = 220,
  });

  final String url;
  final String? coverUrl;
  final double height;

  @override
  State<ItemVideoPlayer> createState() => _ItemVideoPlayerState();
}

Map<String, String> _httpHeadersFor(String url) {
  const ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  final lower = url.toLowerCase();
  if (lower.contains('xhscdn') || lower.contains('xiaohongshu')) {
    return {
      'Referer': 'https://www.xiaohongshu.com/',
      'User-Agent': ua,
    };
  }
  if (lower.contains('weibo') ||
      lower.contains('weibocdn') ||
      lower.contains('sinaimg') ||
      lower.contains('sina.com')) {
    return {
      'Referer': 'https://weibo.com/',
      'User-Agent': ua,
    };
  }
  return {'User-Agent': ua};
}

class _ItemVideoPlayerState extends State<ItemVideoPlayer> {
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _showControls = true;
  bool _inFullscreen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ItemVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _init();
    }
  }

  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _initializing = false;
        _error = '视频链接无效';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: _httpHeadersFor(widget.url),
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
      setState(() {
        _initializing = false;
        _error = '无法播放（链接可能已过期）';
      });
    }
  }

  void _onTick() {
    if (!mounted || _inFullscreen) return;
    setState(() {});
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    c?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  Future<void> _enterFullscreen() async {
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
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
            const Icon(Icons.error_outline_rounded, color: _muted, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 14, color: _muted),
              ),
            ),
            TextButton(
              onPressed: _init,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

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
                  onDoubleTap: _enterFullscreen,
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
                    onFullscreen: _enterFullscreen,
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
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
