import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/features/items/cover_image.dart';

const _quoteStyle = TextStyle(
  color: Color(0xFF1F242E),
  fontSize: 17,
  height: 1.8,
  letterSpacing: 0.2,
  fontWeight: FontWeight.w400,
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

/// 后台绘摘句图并唤起系统分享面板（与思维导图分享同一条路径）。
Future<void> shareReadingQuote({
  required String quote,
  String? title,
  String? link,
  String? coverUrl,
  String? pageUrl,
  Rect? sharePositionOrigin,
  Size? screenSize,
}) async {
  final bytes = await renderReadingQuotePng(
    quote: quote.trim(),
    title: title?.trim() ?? '',
    link: link?.trim() ?? '',
    coverUrl: coverUrl,
    pageUrl: pageUrl,
  );
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
}

Future<Uint8List> renderReadingQuotePng({
  required String quote,
  String title = '',
  String link = '',
  String? coverUrl,
  String? pageUrl,
  double pixelRatio = 3,
}) async {
  final quotePainter = TextPainter(
    text: TextSpan(text: _closeQuote(quote), style: _quoteStyle),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _cardWidth - _quotePadX * 2);
  final overflows = quotePainter.height > _quoteMaxHeight + 1;
  final quoteHeight = overflows ? _quoteMaxHeight : quotePainter.height;
  final quoteWidth = _cardWidth - _quotePadX * 2;
  final openMark = TextPainter(
    text: const TextSpan(text: '「', style: _quoteStyle),
    textDirection: TextDirection.ltr,
  )..layout();
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

  final coverBlock = cover == null ? 0.0 : _coverHeight;
  final quoteTop = coverBlock + _padTop;
  final contentW = _cardWidth;
  final contentH = quoteTop +
      quoteHeight +
      (footerSlots == 0 ? _padBottom : _footerGap + footerHeight + _padBottom);

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
  if (overflows) {
    _paintEdgeFade(
      canvas,
      Rect.fromLTWH(_quotePadX, quoteTop, quoteWidth, quoteHeight),
    );
  }

  if (footerSlots > 0) {
    final footerTop = quoteTop + quoteHeight + _footerGap;
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
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF000000),
        ),
      ).paint(canvas, const Size(_qrSize, _qrSize));
      canvas.restore();
    }
  }

  quotePainter.dispose();
  openMark.dispose();
  titlePainter?.dispose();

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
    final response = await http.get(
      uri,
      headers: mediaHttpHeadersFor(resolved, pageUrl: pageUrl),
    );
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(response.bodyBytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (error) {
    debugPrint('quote cover load failed: $error');
    return null;
  }
}

String _closeQuote(String quote) {
  var text = quote.trim();
  if (text.startsWith('「')) text = text.substring(1);
  if (text.endsWith('」')) text = text.substring(0, text.length - 1);
  return '$text」';
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
