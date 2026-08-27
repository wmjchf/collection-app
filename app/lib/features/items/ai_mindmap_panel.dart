import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/mindmap_image_export.dart';
import 'package:super_collection/features/items/mindmap_render.dart';

/// 阅读页正文下方：思维导图 loading / 脑图 / 失败
class AiMindmapPanel extends StatefulWidget {
  const AiMindmapPanel({
    super.key,
    required this.mindmapMeta,
    this.sourceTitle,
    this.onRetry,
  });

  final AiMindmapMeta mindmapMeta;
  final String? sourceTitle;
  final VoidCallback? onRetry;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _surface = Color(0xFFF3F6FA);

  @override
  State<AiMindmapPanel> createState() => _AiMindmapPanelState();
}

class _AiMindmapPanelState extends State<AiMindmapPanel> {
  bool _sharing = false;

  Future<void> _shareMindmap(
    AiMindmapNode root, {
    Rect? shareOrigin,
  }) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final screenSize = MediaQuery.sizeOf(context);
      await shareMindmapImage(
        root: root,
        sourceTitle: widget.sourceTitle,
        sharePositionOrigin: shareOrigin,
        screenSize: screenSize,
      );
    } catch (error, stack) {
      debugPrint('mindmap share failed: $error\n$stack');
      if (mounted) {
        AppToast.show(context, '分享失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.mindmapMeta;
    if (meta.status == 'none') {
      return const SizedBox.shrink();
    }

    if (meta.isPending) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _MindmapLoadingCard(awaitTranscript: meta.awaitTranscript),
      );
    }

    if (meta.isFailed) {
      final err = (meta.error ?? '').trim();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '思维导图',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AiMindmapPanel._text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                err.isEmpty ? '思维导图生成失败' : '生成失败：$err',
                style: const TextStyle(
                  fontSize: 13,
                  color: AiMindmapPanel._muted,
                  height: 1.4,
                ),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: widget.onRetry,
                  child: const Text(
                    '重试',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AiMindmapPanel._brand,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!meta.isSuccess || !meta.hasTree) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  '思维导图',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AiMindmapPanel._text,
                    height: 1,
                  ),
                ),
                const Spacer(),
                if (widget.onRetry != null)
                  _MindmapActionIcon(
                    icon: Icons.refresh_rounded,
                    onTap: widget.onRetry,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.white,
                child: MindmapInteractiveView(
                  root: meta.tree!,
                  collapsed: const {},
                  onToggle: (_) {},
                  viewHeight: 280,
                  onPreviewTap: () => showMindmapFullscreen(
                    context,
                    root: meta.tree!,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      '点击思维导图进入全屏；全屏内可折叠节点、双指缩放',
                      style: TextStyle(
                        fontSize: 12,
                        color: AiMindmapPanel._muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MindmapShareButton(
                    loading: _sharing,
                    onTap: _sharing
                        ? null
                        : (origin) =>
                            _shareMindmap(meta.tree!, shareOrigin: origin),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可缩放平移的思维导图视图（内嵌预览与全屏页共用）
class MindmapInteractiveView extends StatefulWidget {
  const MindmapInteractiveView({
    super.key,
    required this.root,
    required this.collapsed,
    required this.onToggle,
    this.viewHeight,
    this.minScale = 0.4,
    this.maxScale = 2.5,
    this.onPreviewTap,
  });

  final AiMindmapNode root;
  final Set<String> collapsed;
  final ValueChanged<String> onToggle;
  final double? viewHeight;
  final double minScale;
  final double maxScale;
  final VoidCallback? onPreviewTap;

  @override
  State<MindmapInteractiveView> createState() => _MindmapInteractiveViewState();
}

class _MindmapInteractiveViewState extends State<MindmapInteractiveView> {
  final _controller = TransformationController();
  final _canvasKey = GlobalKey();
  bool _initialFitDone = false;
  int _activePointers = 0;
  Offset? _pointerDown;
  Matrix4? _pointerDownMatrix;

  static const _tapSlop = 20.0;
  static const _transformSlop = 1.5;
  static const _scaleSlop = 0.015;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MindmapInteractiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root ||
        oldWidget.collapsed != widget.collapsed) {
      _initialFitDone = false;
    }
  }

  void _fitPreviewIfNeeded(double viewportWidth, double viewportHeight) {
    if (_initialFitDone || widget.viewHeight == null || viewportWidth <= 0) {
      return;
    }
    final layout = MindmapLayout.compute(widget.root, widget.collapsed);
    final scale = math.min(
      1.0,
      math.min(
        (viewportWidth - 16) / layout.width,
        (viewportHeight - 16) / layout.height,
      ),
    );
    _controller.value = Matrix4.identity()
      ..translate(8.0, 8.0)
      ..scale(scale);
    _initialFitDone = true;
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers == 1) {
      _pointerDown = event.position;
      _pointerDownMatrix = _controller.value.clone();
    } else {
      _pointerDown = null;
      _pointerDownMatrix = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    final down = _pointerDown;
    final startMatrix = _pointerDownMatrix;
    if (_activePointers != 0 || down == null || startMatrix == null) {
      if (_activePointers == 0) {
        _pointerDown = null;
        _pointerDownMatrix = null;
      }
      return;
    }

    final moved = (event.position - down).distance;
    final transformChanged =
        !_matricesSimilar(startMatrix, _controller.value);
    _pointerDown = null;
    _pointerDownMatrix = null;

    if (moved >= _tapSlop || transformChanged) return;

    if (widget.onPreviewTap != null) {
      widget.onPreviewTap!();
      return;
    }

    final path = _hitTestNode(event.position);
    if (path != null) {
      widget.onToggle(path);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (_activePointers == 0) {
      _pointerDown = null;
      _pointerDownMatrix = null;
    }
  }

  bool _matricesSimilar(Matrix4 a, Matrix4 b) {
    if ((a.getMaxScaleOnAxis() - b.getMaxScaleOnAxis()).abs() > _scaleSlop) {
      return false;
    }
    final ta = a.getTranslation();
    final tb = b.getTranslation();
    return (Offset(ta.x, ta.y) - Offset(tb.x, tb.y)).distance < _transformSlop;
  }

  String? _hitTestNode(Offset globalPosition) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalPosition);
    final layout = MindmapLayout.compute(widget.root, widget.collapsed);
    for (final node in layout.nodes.values) {
      if (node.rect.contains(local)) {
        return node.path;
      }
    }
    return null;
  }

  Widget _wrapPointerHandler(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewer = InteractiveViewer(
      transformationController: _controller,
      constrained: false,
      alignment: Alignment.topLeft,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      boundaryMargin: const EdgeInsets.all(80),
      clipBehavior: Clip.none,
      child: _MindmapCanvas(
        key: _canvasKey,
        root: widget.root,
        collapsed: widget.collapsed,
      ),
    );

    final wrapped = _wrapPointerHandler(viewer);

    if (widget.viewHeight != null) {
      return SizedBox(
        height: widget.viewHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitPreviewIfNeeded(
                constraints.maxWidth,
                widget.viewHeight!,
              );
            });
            return wrapped;
          },
        ),
      );
    }
    return wrapped;
  }
}

/// 全屏预览思维导图
void showMindmapFullscreen(
  BuildContext context, {
  required AiMindmapNode root,
  Set<String>? initialCollapsed,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => MindmapFullscreenPage(
        root: root,
        initialCollapsed: initialCollapsed,
      ),
    ),
  );
}

class MindmapFullscreenPage extends StatefulWidget {
  const MindmapFullscreenPage({
    super.key,
    required this.root,
    this.initialCollapsed,
  });

  final AiMindmapNode root;
  final Set<String>? initialCollapsed;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  State<MindmapFullscreenPage> createState() => _MindmapFullscreenPageState();
}

class _MindmapFullscreenPageState extends State<MindmapFullscreenPage> {
  late final Set<String> _collapsed;
  bool _landscape = false;

  @override
  void initState() {
    super.initState();
    _collapsed = Set<String>.from(widget.initialCollapsed ?? {});
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _toggleCollapsed(String path) {
    setState(() {
      if (_collapsed.contains(path)) {
        _collapsed.remove(path);
      } else {
        _collapsed.add(path);
      }
    });
  }

  void _toggleScreenRotation() {
    setState(() {
      _landscape = !_landscape;
    });
    SystemChrome.setPreferredOrientations(
      _landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: MindmapFullscreenPage._text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '思维导图',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: MindmapFullscreenPage._text,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _landscape ? '竖屏' : '横屏',
            icon: Icon(
              _landscape
                  ? Icons.screen_lock_portrait_rounded
                  : Icons.screen_rotation_alt_rounded,
              color: MindmapFullscreenPage._muted,
            ),
            onPressed: _toggleScreenRotation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: MindmapInteractiveView(
                root: widget.root,
                collapsed: _collapsed,
                onToggle: _toggleCollapsed,
                minScale: 0.3,
                maxScale: 3.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Text(
              '点击节点可折叠/展开分支；双指缩放查看',
              style: TextStyle(
                fontSize: 12,
                color: MindmapFullscreenPage._muted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _MindmapCanvas extends StatelessWidget {
  const _MindmapCanvas({
    super.key,
    required this.root,
    required this.collapsed,
  });

  final AiMindmapNode root;
  final Set<String> collapsed;

  @override
  Widget build(BuildContext context) {
    final layout = MindmapLayout.compute(root, collapsed);
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: CustomPaint(
        size: Size(layout.width, layout.height),
        painter: MindmapPainter(layout: layout),
      ),
    );
  }
}

class _MindmapShareButton extends StatelessWidget {
  const _MindmapShareButton({
    required this.onTap,
    this.loading = false,
  });

  final void Function(Rect? shareOrigin)? onTap;
  final bool loading;

  static Rect? _shareOriginFor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(_shareOriginFor(context)),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AiMindmapPanel._brand.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AiMindmapPanel._brand.withValues(alpha: 0.85),
                ),
              )
            else
              const Icon(
                Icons.ios_share_rounded,
                size: 16,
                color: AiMindmapPanel._brand,
              ),
            const SizedBox(width: 4),
            const Text(
              '分享',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AiMindmapPanel._brand,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MindmapActionIcon extends StatelessWidget {
  const _MindmapActionIcon({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  static const _iconSize = 18.0;
  static const _hitSize = 26.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _hitSize,
        height: _hitSize,
        child: Center(
          child: Icon(
            icon,
            size: _iconSize,
            color: AiMindmapPanel._muted,
          ),
        ),
      ),
    );
  }
}

class _MindmapLoadingCard extends StatelessWidget {
  const _MindmapLoadingCard({this.awaitTranscript = false});

  final bool awaitTranscript;

  @override
  Widget build(BuildContext context) {
    final title = awaitTranscript
        ? '正在转写，完成后生成思维导图…'
        : '正在生成思维导图…';
    final subtitle = awaitTranscript
        ? '转写完成后将自动开始生成'
        : '完成后可缩放查看结构';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AiMindmapPanel._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AiMindmapPanel._brand.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AiMindmapPanel._muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AiMindmapPanel._muted.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AiMindmapPanel._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
