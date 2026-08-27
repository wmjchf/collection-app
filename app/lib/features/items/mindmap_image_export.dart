import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/mindmap_render.dart';

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

/// 脑图区域斜向平铺半透明 CONFLUX 水印（不遮挡阅读）。
void _paintConfluxWatermark(Canvas canvas, Size size) {
  const text = 'CONFLUX';
  const style = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 3,
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
    return 'Conflux';
  }
  return '$title · Conflux';
}

Future<File> writeMindmapPngFile(Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/mindmap_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// 导出完整脑图 PNG 并唤起系统分享面板（微信等）。
Future<void> shareMindmapImage({
  required BuildContext context,
  required AiMindmapNode root,
  String? sourceTitle,
}) async {
  Rect? shareOrigin;
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    shareOrigin = box.localToGlobal(Offset.zero) & box.size;
  }

  final bytes = await renderMindmapPngBytes(
    root: root,
    sourceTitle: sourceTitle,
  );
  final file = await writeMindmapPngFile(bytes);

  final title = sourceTitle?.trim();
  final shareText = (title != null && title.isNotEmpty)
      ? '思维导图：$title'
      : '思维导图';

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: shareText,
      subject: shareText,
      sharePositionOrigin: shareOrigin,
    ),
  );
}
