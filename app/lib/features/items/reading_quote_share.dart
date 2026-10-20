import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/justified_text.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

const _quoteStyle = TextStyle(
  color: Color(0xFF1F242E),
  fontSize: 16,
  height: 1.8,
  letterSpacing: 0.2,
  fontWeight: FontWeight.w400,
);

const _markStyle = TextStyle(
  color: Color(0xFFB7C3B4),
  fontSize: 22,
  height: 1,
  fontWeight: FontWeight.w500,
);

const _cardWidth = 360.0;
const _quotePadX = 32.0;
const _footerPadX = 24.0;
const _padTop = 28.0;
const _padBottom = 20.0;
const _quoteMaxHeight = 300.0;
const _footerGap = 72.0;
const _coverHeight = 180.0;
const _qrSize = 64.0;
const _qrGap = 32.0;
const _watermarkGap = 10.0;
const _watermarkText = 'iOS App Store 下载奏折';
const _watermarkStyle = TextStyle(
  color: Color(0xFFC5CDD4),
  fontSize: 11,
  height: 1.2,
  letterSpacing: 0.4,
  fontWeight: FontWeight.w500,
);

/// 分享图的三种正文来源，卡片上用类型名区分。
enum ReadingShareKind {
  quote,
  summary,
  note,
  annotation;

  String get label => switch (this) {
        ReadingShareKind.quote => '摘句',
        ReadingShareKind.summary => 'AI 总结',
        ReadingShareKind.note => '感想',
        ReadingShareKind.annotation => '批注',
      };
}

const _annotationStyle = TextStyle(
  color: Color(0xFF5C6370),
  fontSize: 14,
  height: 1.7,
  fontWeight: FontWeight.w400,
);

const _annotationGap = 20.0;

const _kindStyle = TextStyle(
  color: Color(0xFF8FA394),
  fontSize: 12,
  height: 1.2,
  letterSpacing: 1.2,
  fontWeight: FontWeight.w600,
);

bool _quoteShareInFlight = false;

/// 后台绘摘句图并唤起系统分享面板（与思维导图分享同一条路径）。
/// 出图完成前在屏幕中央转圈，系统面板弹出前关掉。
Future<void> shareReadingQuote({
  required BuildContext context,
  required String quote,
  String? title,
  String? link,
  String? coverUrl,
  String? pageUrl,
  String? note,
  ReadingShareKind kind = ReadingShareKind.quote,
  Rect? sharePositionOrigin,
  Size? screenSize,
}) async {
  if (_quoteShareInFlight) return;
  _quoteShareInFlight = true;
  final loading = _QuoteShareLoading.show(context);
  try {
    final annotation = note?.trim() ?? '';
    final bytes = await renderReadingQuotePng(
      quote: quote.trim(),
      title: title?.trim() ?? '',
      link: link?.trim() ?? '',
      coverUrl: coverUrl,
      pageUrl: pageUrl,
      kind: annotation.isNotEmpty && kind == ReadingShareKind.quote
          ? ReadingShareKind.annotation
          : kind,
      note: annotation,
      watermark: await _shareWatermark(),
    );
    loading.dismiss();
    final origin = _effectiveShareOrigin(sharePositionOrigin, screenSize);
    final file = XFile.fromData(
      bytes,
      mimeType: 'image/png',
      name: 'quote.png',
    );
    await _shareWithFallback(
      ShareParams(
        files: [file],
        fileNameOverrides: const ['quote.png'],
        sharePositionOrigin: origin,
      ),
    );
  } finally {
    loading.dismiss();
    _quoteShareInFlight = false;
  }
}

Future<Uint8List> renderReadingQuotePng({
  required String quote,
  String title = '',
  String link = '',
  String? coverUrl,
  String? pageUrl,
  ReadingShareKind kind = ReadingShareKind.quote,
  String note = '',
  bool watermark = false,
  double pixelRatio = 3,
}) async {
  final plain = _plainQuote(quote);
  final quotePainter = TextPainter(
    text: TextSpan(text: plain, style: _quoteStyle),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _cardWidth - _quotePadX * 2);
  final overflows = kind != ReadingShareKind.summary &&
      quotePainter.height > _quoteMaxHeight + 1;
  final quoteHeight = overflows ? _quoteMaxHeight : quotePainter.height;
  final quoteWidth = _cardWidth - _quotePadX * 2;
  final openMark = TextPainter(
    text: const TextSpan(text: '「', style: _markStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  final closeMark = TextPainter(
    text: const TextSpan(text: '」', style: _markStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  final kindPainter = TextPainter(
    text: TextSpan(text: kind.label, style: _kindStyle),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _cardWidth - _quotePadX * 2);
  const kindGap = 12.0;
  final cover = await _loadCover(coverUrl, pageUrl);
  final hasTitle = title.isNotEmpty;
  final hasQr = link.isNotEmpty;
  final footerSlots = (hasTitle ? 1 : 0) + (hasQr ? 1 : 0);
  final reservedGaps = hasQr && hasTitle ? _qrGap : 0.0;
  final footerWidth = _cardWidth - _footerPadX * 2;
  final titleMaxWidth = math.max(
    0.0,
    footerWidth - (hasQr ? _qrSize : 0) - reservedGaps,
  );
  TextPainter? titlePainter;
  if (hasTitle) {
    titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFF1F242E),
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: titleMaxWidth);
  }
  final footerHeight = footerSlots == 0
      ? 0.0
      : math.max(titlePainter?.height ?? 0, hasQr ? _qrSize : 0);

  TextPainter? watermarkPainter;
  if (watermark) {
    watermarkPainter = TextPainter(
      text: const TextSpan(text: _watermarkText, style: _watermarkStyle),
      textDirection: TextDirection.ltr,
    )..layout();
  }
  final watermarkBlock = watermarkPainter == null
      ? 0.0
      : _watermarkGap + watermarkPainter.height;

  final annotation = note.trim();
  final annotationLines = annotation.isEmpty
      ? const <JustifiedLine>[]
      : layoutJustifiedLines(
          annotation,
          _annotationStyle,
          _cardWidth - _quotePadX * 2,
        );
  final annotationPainters = <TextPainter>[
    for (final line in annotationLines)
      TextPainter(
        text: TextSpan(
          text: line.text.isEmpty ? ' ' : line.text,
          style: line.spacing == 0
              ? _annotationStyle
              : _annotationStyle.copyWith(letterSpacing: line.spacing),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(),
  ];
  final annotationHeight = annotationPainters.fold<double>(
    0,
    (sum, painter) => sum + painter.height,
  );
  final annotationBlock =
      annotationPainters.isEmpty ? 0.0 : _annotationGap + annotationHeight;

  final coverBlock = cover == null ? 0.0 : _coverHeight;
  final kindTop = coverBlock + _padTop;
  final quoteTop = kindTop + kindPainter.height + kindGap;
  final contentW = _cardWidth;
  final contentH = quoteTop +
      quoteHeight +
      annotationBlock +
      (footerSlots == 0 ? 0.0 : _footerGap + footerHeight) +
      watermarkBlock +
      _padBottom;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, contentW, contentH),
    Paint()..color = Colors.white,
  );

  if (cover != null) {
    _paintCover(
      canvas,
      cover,
      Rect.fromLTWH(0, 0, contentW, _coverHeight),
      contain: CoverImage.isBrandIconUrl(coverUrl),
      circular: false,
    );
    cover.dispose();
  }

  final kindGlyphTop = kindPainter
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .firstOrNull
      ?.top;
  kindPainter.paint(
    canvas,
    Offset(_quotePadX, kindTop - (kindGlyphTop ?? 0)),
  );

  canvas.save();
  canvas.clipRect(Rect.fromLTWH(_quotePadX, quoteTop, quoteWidth, quoteHeight));
  quotePainter.paint(canvas, Offset(_quotePadX, quoteTop));
  canvas.restore();
  final quoteGlyphTop = quotePainter
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .firstOrNull
      ?.top;
  final openGlyphTop = openMark
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .firstOrNull
      ?.top;
  openMark.paint(
    canvas,
    Offset(
      _quotePadX - openMark.width - 4,
      quoteTop + (quoteGlyphTop ?? 0) - (openGlyphTop ?? 0),
    ),
  );
  if (plain.isNotEmpty) {
    final closeGlyphTop = closeMark
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .firstOrNull
        ?.top;
    final closeAt = _closeMarkAnchor(
      quotePainter,
      quoteHeight: quoteHeight,
      overflows: overflows,
    );
    closeMark.paint(
      canvas,
      Offset(
        _quotePadX + closeAt.dx + 2,
        quoteTop + closeAt.dy - (closeGlyphTop ?? 0),
      ),
    );
  }
  if (overflows) {
    _paintEdgeFade(
      canvas,
      Rect.fromLTWH(_quotePadX, quoteTop, quoteWidth, quoteHeight),
    );
  }
  if (annotationPainters.isNotEmpty) {
    var annotationTop = quoteTop + quoteHeight + _annotationGap;
    for (final painter in annotationPainters) {
      painter.paint(canvas, Offset(_quotePadX, annotationTop));
      annotationTop += painter.height;
    }
  }

  if (footerSlots > 0) {
    final footerTop = quoteTop + quoteHeight + annotationBlock + _footerGap;
    if (titlePainter != null) {
      final glyphTop = titlePainter
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .firstOrNull
          ?.top;
      titlePainter.paint(
        canvas,
        Offset(_footerPadX, footerTop - (glyphTop ?? 0)),
      );
    }
    if (hasQr) {
      canvas.save();
      canvas.translate(
        contentW - _footerPadX - _qrSize,
        footerTop + (footerHeight - _qrSize) / 2,
      );
      QrPainter(
        data: link,
        version: QrVersions.auto,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.circle,
          color: Color(0xFF1F242E),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.circle,
          color: Color(0xFF1F242E),
        ),
      ).paint(canvas, const Size(_qrSize, _qrSize));
      canvas.restore();
    }
  }

  if (watermarkPainter != null) {
    watermarkPainter.paint(
      canvas,
      Offset(
        contentW - _footerPadX - watermarkPainter.width,
        contentH - _padBottom - watermarkPainter.height,
      ),
    );
  }

  quotePainter.dispose();
  openMark.dispose();
  closeMark.dispose();
  kindPainter.dispose();
  titlePainter?.dispose();
  watermarkPainter?.dispose();
  for (final painter in annotationPainters) {
    painter.dispose();
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (contentW * pixelRatio).ceil(),
    (contentH * pixelRatio).ceil(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('quote PNG encode failed');
  return data.buffer.asUint8List();
}

void _paintCover(
  Canvas canvas,
  ui.Image image,
  Rect dest, {
  required bool contain,
  bool circular = false,
}) {
  canvas.save();
  if (circular) {
    canvas.clipPath(Path()..addOval(dest));
  } else {
    canvas.clipRect(dest);
  }
  if (contain) {
    canvas.drawRect(dest, Paint()..color = Colors.white);
    final scale = math.min(dest.width / image.width, dest.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(dest.left + (dest.width - w) / 2, dest.top + (dest.height - h) / 2, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
  } else {
    canvas.drawImageRect(
      image,
      _coverSourceRect(image, dest.size),
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
  canvas.restore();
}

Rect _coverSourceRect(ui.Image image, Size dest) {
  final iw = image.width.toDouble();
  final ih = image.height.toDouble();
  final scale = math.max(dest.width / iw, dest.height / ih);
  final sw = dest.width / scale;
  final sh = dest.height / scale;
  return Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh);
}

Future<ui.Image?> _loadCover(String? url, String? pageUrl) async {
  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return null;
  final resolved = resolveMediaUrl(raw);
  final uri = Uri.tryParse(resolved);
  if (uri == null || !uri.hasScheme) return null;
  try {
    final provider = NetworkImage(
      resolved,
      headers: mediaHttpHeadersFor(resolved, pageUrl: pageUrl),
    );
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<ui.Image?>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final copy = info.image.clone();
        if (!completer.isCompleted) {
          completer.complete(copy);
        } else {
          copy.dispose();
        }
      },
      onError: (Object error, StackTrace? _) {
        debugPrint('quote cover load failed: $error');
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  } catch (error) {
    debugPrint('quote cover load failed: $error');
    return null;
  }
}

/// 免费档带水印；普通会员、太子、帝王不带。查不到档位时按免费处理。
Future<bool> _shareWatermark() async {
  try {
    final usage = UsageRefresh.snapshot ?? await UsageRefresh.ensure();
    return !usage.isPaid;
  } catch (error) {
    debugPrint('share watermark plan lookup failed: $error');
    return true;
  }
}

String _plainQuote(String quote) {
  var text = quote.trim();
  if (text.startsWith('「')) text = text.substring(1);
  if (text.endsWith('」')) text = text.substring(0, text.length - 1);
  return text;
}

/// 结尾引号跟在最后一字右侧；正文被裁切时跟在可见末字右侧。
Offset _closeMarkAnchor(
  TextPainter painter, {
  required double quoteHeight,
  required bool overflows,
}) {
  final length = painter.plainText.length;
  if (length == 0) return Offset.zero;
  var end = length;
  if (overflows) {
    final pos = painter.getPositionForOffset(Offset(painter.width, quoteHeight - 1));
    end = pos.offset.clamp(1, length);
  }
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: end - 1, extentOffset: end),
  );
  final box = boxes.lastOrNull;
  if (box == null) return Offset.zero;
  return Offset(box.right, box.top);
}

void _paintEdgeFade(Canvas canvas, Rect quoteRect) {
  const edge = 28.0;
  final top = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Color(0x00FFFFFF)],
    ).createShader(Rect.fromLTWH(quoteRect.left, quoteRect.top, quoteRect.width, edge));
  canvas.drawRect(
    Rect.fromLTWH(quoteRect.left, quoteRect.top, quoteRect.width, edge),
    top,
  );
  final bottom = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Colors.white, Color(0x00FFFFFF)],
    ).createShader(
      Rect.fromLTWH(
        quoteRect.left,
        quoteRect.bottom - edge,
        quoteRect.width,
        edge,
      ),
    );
  canvas.drawRect(
    Rect.fromLTWH(
      quoteRect.left,
      quoteRect.bottom - edge,
      quoteRect.width,
      edge,
    ),
    bottom,
  );
}

class _QuoteShareLoading {
  _QuoteShareLoading(this._entry);

  final OverlayEntry? _entry;
  var _dismissed = false;

  static _QuoteShareLoading show(BuildContext context) {
    if (!context.mounted) return _QuoteShareLoading(null);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return _QuoteShareLoading(null);
    final entry = OverlayEntry(
      builder: (context) => const AbsorbPointer(
        child: Center(
          child: Material(
            color: Color(0xFF1F242E),
            borderRadius: BorderRadius.all(Radius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    return _QuoteShareLoading(entry);
  }

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    final entry = _entry;
    if (entry != null && entry.mounted) entry.remove();
  }
}

Future<void> _shareWithFallback(ShareParams params) async {
  try {
    await SharePlus.instance.share(params);
  } catch (error) {
    final origin = params.sharePositionOrigin;
    if (origin == null || origin == Rect.zero) rethrow;
    debugPrint('quote share retry without origin: $error');
    await SharePlus.instance.share(
      ShareParams(
        files: params.files,
        fileNameOverrides: params.fileNameOverrides,
      ),
    );
  }
}

Rect _effectiveShareOrigin(Rect? buttonOrigin, Size? screenSize) {
  if (screenSize == null) {
    return buttonOrigin ?? Rect.zero;
  }
  final screen = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
  if (buttonOrigin != null &&
      buttonOrigin.width > 0 &&
      buttonOrigin.height > 0 &&
      screen.overlaps(buttonOrigin.inflate(1))) {
    return buttonOrigin;
  }
  return Rect.fromLTWH(
    screenSize.width * 0.5 - 1,
    screenSize.height * 0.82,
    2,
    2,
  );
}
