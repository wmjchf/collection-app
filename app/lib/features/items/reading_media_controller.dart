import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 阅读页级音频播放（小宇宙等播客）：不依赖 ListView 内 Platform View；前台可续播（未声明 iOS 后台 audio）。
class ReadingMediaController extends ChangeNotifier {
  ReadingMediaController() {
    _playerStateSub = player.playerStateStream.listen((_) => _safeNotify());
    _positionSub = player.positionStream.listen((_) => _safeNotify());
    _durationSub = player.durationStream.listen((_) => _safeNotify());
  }

  final AudioPlayer player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  String? _loadedUrl;
  bool initializing = false;
  String? error;
  bool _disposed = false;

  static var _sessionConfigured = false;

  bool get isPlaying => player.playing;
  Duration get position => player.position;
  Duration? get duration => player.duration;

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  static Future<void> ensureAudioSession() async {
    if (_sessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
    _sessionConfigured = true;
  }

  Future<void> loadUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      error = '音频链接无效';
      _safeNotify();
      return;
    }
    if (_loadedUrl == trimmed && player.audioSource != null) {
      error = null;
      _safeNotify();
      return;
    }

    initializing = true;
    error = null;
    _safeNotify();

    try {
      await ensureAudioSession();
      if (_disposed) return;
      await player.setAudioSource(
        AudioSource.uri(Uri.parse(trimmed), headers: headers),
      );
      if (_disposed) return;
      _loadedUrl = trimmed;
    } catch (_) {
      if (_disposed) return;
      _loadedUrl = null;
      error = '无法播放（链接失效或网络异常，可点重试）';
    }

    if (_disposed) return;
    initializing = false;
    _safeNotify();
  }

  Future<void> togglePlay() async {
    if (_disposed) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await player.seek(position);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_playerStateSub?.cancel());
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    _playerStateSub = null;
    _positionSub = null;
    _durationSub = null;
    unawaited(player.dispose());
    super.dispose();
  }
}

/// 是否走 just_audio（播客/纯音频），而非 VideoPlayer Platform View。
bool isAudioOnlyMediaUrl(String url, {String? platform}) {
  final p = platform?.trim().toLowerCase();
  if (p == 'xiaoyuzhou') return true;

  final lower = url.trim().toLowerCase();
  if (lower.isEmpty) return false;
  if (lower.contains('bilivideo') ||
      lower.contains('bilibili.com') ||
      lower.contains('hdslb.com') ||
      lower.contains('gtimg.com') ||
      lower.contains('weibocdn') ||
      lower.contains('toutiaovod')) {
    return false;
  }

  if (lower.contains('xiaoyuzhoufm.com') ||
      lower.contains('xyzcdn.net') ||
      lower.contains('/audio/')) {
    return true;
  }

  final path = Uri.tryParse(lower)?.path.toLowerCase() ?? lower;
  const exts = ['.m4a', '.mp3', '.aac', '.wav', '.ogg', '.flac', '.opus'];
  for (final ext in exts) {
    if (path.endsWith(ext) || lower.contains('$ext?')) return true;
  }
  return false;
}
