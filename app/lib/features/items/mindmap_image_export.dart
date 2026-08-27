import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/mindmap_render.dart';

/// 分享 PNG 页脚品牌行；平铺水印仅用短名 [_shareBrandShort]。
const _shareBrandShort = 'Conflux';
const _shareBrandLine = 'Conflux不再吃灰的收藏夹';

/// 微信等对体积/尺寸敏感：长边与文件大小上限。
const _shareMaxLongSide = 3072.0;
const _shareMaxBytes = 8 * 1024 * 1024;

/// 离屏渲染完整展开的思维导图为 PNG（忽略折叠状态）。
Future<Uint8List> renderMindmapPngBytes({
  required AiMindmapNode root,
  String? sourceTitle,
  double pixelRatio = 2.0,
}) async {
  const hPad = 24.0;
  const vPad = 24.0;
  const footerGap = 12.0;
  const footerHeight = 20.0;
  const maxSide = 8192.0;

  final layout = MindmapLayout.compute(root, const {});
  final footer = _footerText(sourceTitle);
  final footerBlock = footer == null ? 0.0 : footerGap + footerHeight;

  final contentW = layout.width + hPad * 2;
  final contentH = layout.height + vPad * 2 + footerBlock;

  var ratio = pixelRatio;
  if (contentW * ratio > maxSide || contentH * ratio > maxSide) {
    ratio = math.min(maxSide / contentW, maxSide / contentH);
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);

  canvas.drawRect(
    Rect.fromLTWH(0, 0, contentW, contentH),
    Paint()..color = Colors.white,
  );

  canvas.save();
  canvas.translate(hPad, vPad);
  MindmapPainter(layout: layout).paint(canvas, Size(layout.width, layout.height));
  _paintConfluxWatermark(
    canvas,
    Size(layout.width, layout.height),
  );
  canvas.restore();

  if (footer != null) {
    final tp = TextPainter(
      text: TextSpan(
        text: footer,
        style: const TextStyle(
          fontSize: 12,
          height: 1.2,
          color: Color(0xFF737A85),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: contentW - hPad * 2);

    tp.paint(
      canvas,
      Offset(
        (contentW - tp.width) / 2,
        vPad + layout.height + footerGap,
      ),
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (contentW * ratio).ceil(),
    (contentH * ratio).ceil(),
  );
  final byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('PNG encode failed');
  }
  return byteData.buffer.asUint8List();
}

/// 为分享导出 PNG：自动压低像素比，避免微信因过大图片失败。
Future<Uint8List> renderMindmapPngBytesForShare({
  required AiMindmapNode root,
  String? sourceTitle,
}) async {
  final layout = MindmapLayout.compute(root, const {});
  const hPad = 24.0;
  const vPad = 24.0;
  const footerGap = 12.0;
  const footerHeight = 20.0;
  final footer = _footerText(sourceTitle);
  final footerBlock = footer == null ? 0.0 : footerGap + footerHeight;
  final contentW = layout.width + hPad * 2;
  final contentH = layout.height + vPad * 2 + footerBlock;
  final longSide = math.max(contentW, contentH);

  var ratio = 2.0;
  if (longSide * ratio > _shareMaxLongSide) {
    ratio = _shareMaxLongSide / longSide;
  }

  Uint8List bytes = await renderMindmapPngBytes(
    root: root,
    sourceTitle: sourceTitle,
    pixelRatio: ratio,
  );

  for (var i = 0; i < 4 && bytes.length > _shareMaxBytes; i++) {
    ratio *= 0.72;
    bytes = await renderMindmapPngBytes(
      root: root,
      sourceTitle: sourceTitle,
      pixelRatio: ratio,
    );
  }

  if (bytes.length > _shareMaxBytes) {
    throw StateError(
      'Mindmap image too large for share (${bytes.length} bytes)',
    );
  }
  return bytes;
}

/// 脑图区域斜向平铺半透明 Conflux 水印（不遮挡阅读）。
void _paintConfluxWatermark(Canvas canvas, Size size) {
  const text = _shareBrandShort;
  const style = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 2,
    color: Color(0x0D1F242E),
  );

  canvas.save();
  canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
  canvas.translate(size.width / 2, size.height / 2);
  canvas.rotate(-math.pi / 6);

  final tp = TextPainter(
    text: const TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  const stepX = 260.0;
  const stepY = 168.0;
  final spanW = size.width + size.height;
  final spanH = size.height + size.width;

  for (var y = -spanH; y < spanH; y += stepY) {
    for (var x = -spanW; x < spanW; x += stepX) {
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, y - tp.height / 2),
      );
    }
  }
  canvas.restore();
}

String? _footerText(String? sourceTitle) {
  final title = sourceTitle?.trim();
  if (title == null || title.isEmpty) {
    return _shareBrandLine;
  }
  return '$title · $_shareBrandLine';
}

/// 导出完整脑图 PNG 并唤起系统分享面板（微信等）。
Future<void> shareMindmapImage({
  required AiMindmapNode root,
  String? sourceTitle,
  Rect? sharePositionOrigin,
  Size? screenSize,
}) async {
  final bytes = await renderMindmapPngBytesForShare(
    root: root,
    sourceTitle: sourceTitle,
  );

  final origin = _effectiveShareOrigin(
    sharePositionOrigin,
    screenSize,
  );

  final file = XFile.fromData(
    bytes,
    mimeType: 'image/png',
    name: 'mindmap.png',
  );

  await _shareWithFallback(
    ShareParams(
      files: [file],
      fileNameOverrides: const ['mindmap.png'],
      sharePositionOrigin: origin,
    ),
  );
}

Future<void> _shareWithFallback(ShareParams params) async {
  try {
    await SharePlus.instance.share(params);
  } catch (error) {
    final origin = params.sharePositionOrigin;
    if (origin == null || origin == Rect.zero) {
      rethrow;
    }
    debugPrint('mindmap share retry without origin: $error');
    await SharePlus.instance.share(
      ShareParams(
        files: params.files,
        fileNameOverrides: params.fileNameOverrides,
      ),
    );
  }
}

/// 滚动页里按钮 global rect 可能偏屏外；iOS 26+ 又要求有效锚点。
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

  // 落在屏幕中下，供 iOS share sheet / 微信扩展取锚点
  return Rect.fromLTWH(
    screenSize.width * 0.5 - 1,
    screenSize.height * 0.82,
    2,
    2,
  );
}
