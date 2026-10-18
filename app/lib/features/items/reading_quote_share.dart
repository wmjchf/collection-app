import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_collection/core/config/app_brand.dart';

const _quoteStyle = TextStyle(
  color: Color(0xFF1F242E),
  fontSize: 17,
  height: 1.75,
  fontWeight: FontWeight.w400,
);

const _tagline = '喜欢的内容收藏到一处\n像看奏折一样阅读、整理、思考';

const _cardWidth = 360.0;
const _padX = 24.0;
const _padTop = 28.0;
const _padBottom = 20.0;
const _quoteMaxHeight = 300.0;
const _footerGap = 28.0;
const _qrSize = 64.0;
const _iconSize = 36.0;

/// 后台绘摘句图并唤起系统分享面板（与思维导图分享同一条路径）。
Future<void> shareReadingQuote({
  required String quote,
  required String title,
  required String link,
  Rect? sharePositionOrigin,
  Size? screenSize,
}) async {
  final bytes = await renderReadingQuotePng(
    quote: quote.trim(),
    title: title.trim(),
    link: link.trim(),
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
  required String title,
  required String link,
  double pixelRatio = 3,
}) async {
  final icon = await _loadAppIcon();
  final quotePainter = TextPainter(
    text: TextSpan(text: quote, style: _quoteStyle),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _cardWidth - _padX * 2);
  final overflows = quotePainter.height > _quoteMaxHeight + 1;
  final quoteHeight = overflows ? _quoteMaxHeight : quotePainter.height;
  final quoteWidth = _cardWidth - _padX * 2;

  TextPainter? sourcePainter;
  if (title.isNotEmpty) {
    sourcePainter = TextPainter(
      text: TextSpan(
        text: '—— 《$title》',
        style: const TextStyle(
          color: Color(0xFF1F242E),
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: quoteWidth);
  }
  const sourceGap = 16.0;
  final sourceBlock =
      sourcePainter == null ? 0.0 : sourceGap + sourcePainter.height;

  final namePainter = TextPainter(
    text: const TextSpan(
      text: AppBrand.name,
      style: TextStyle(
        color: Color(0xFF1F242E),
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  final showQr = link.isNotEmpty;
  final footerTextWidth = _cardWidth -
      _padX * 2 -
      _iconSize -
      10 -
      (showQr ? 12 + _qrSize : 0);
  namePainter.layout(maxWidth: footerTextWidth);

  final taglinePainter = TextPainter(
    text: const TextSpan(
      text: _tagline,
      style: TextStyle(
        color: Color(0xFF5C6570),
        fontSize: 11,
        height: 1.35,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: footerTextWidth);

  final textBlock = namePainter.height + 4 + taglinePainter.height;
  final footerHeight = textBlock > _qrSize ? textBlock : _qrSize;
  final contentW = _cardWidth;
  final contentH = _padTop +
      quoteHeight +
      sourceBlock +
      _footerGap +
      footerHeight +
      _padBottom;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, contentW, contentH),
    Paint()..color = Colors.white,
  );

  canvas.save();
  canvas.clipRect(Rect.fromLTWH(_padX, _padTop, quoteWidth, quoteHeight));
  quotePainter.paint(canvas, const Offset(_padX, _padTop));
  canvas.restore();
  if (overflows) {
    _paintEdgeFade(
      canvas,
      Rect.fromLTWH(_padX, _padTop, quoteWidth, quoteHeight),
    );
  }
  sourcePainter?.paint(
    canvas,
    Offset(_padX, _padTop + quoteHeight + sourceGap),
  );

  final footerTop = _padTop + quoteHeight + sourceBlock + _footerGap;
  _paintIcon(
    canvas,
    icon,
    Offset(_padX, footerTop + (footerHeight - _iconSize) / 2),
  );

  final textTop = footerTop + (footerHeight - textBlock) / 2;
  namePainter.paint(canvas, Offset(_padX + _iconSize + 10, textTop));
  taglinePainter.paint(
    canvas,
    Offset(_padX + _iconSize + 10, textTop + namePainter.height + 4),
  );

  if (showQr) {
    canvas.save();
    canvas.translate(
      contentW - _padX - _qrSize,
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

  quotePainter.dispose();
  sourcePainter?.dispose();
  namePainter.dispose();
  taglinePainter.dispose();
  icon.dispose();

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

void _paintIcon(Canvas canvas, ui.Image icon, Offset origin) {
  canvas.save();
  canvas.clipPath(
    Path()..addOval(Rect.fromLTWH(origin.dx, origin.dy, _iconSize, _iconSize)),
  );
  canvas.drawImageRect(
    icon,
    Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
    Rect.fromLTWH(origin.dx, origin.dy, _iconSize, _iconSize),
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
}

Future<ui.Image> _loadAppIcon() async {
  final data = await rootBundle.load('assets/branding/app_icon.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
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
