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
  final _collapsed = <String>{};

  void _toggleCollapsed(String path) {
    setState(() {
      if (_collapsed.contains(path)) {
        _collapsed.remove(path);
      } else {
        _collapsed.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.mindmapMeta;
    if (meta.status == 'none') {
      return const SizedBox.shrink();
    }

    if (meta.isPending) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: _MindmapLoadingCard(),
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
              children: [
                const Text(
                  '思维导图',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AiMindmapPanel._text,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => showMindmapFullscreen(
                    context,
                    root: meta.tree!,
                    sourceTitle: widget.sourceTitle,
                    initialCollapsed: Set<String>.from(_collapsed),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      size: 18,
                      color: AiMindmapPanel._muted,
                    ),
                  ),
                ),
                if (widget.onRetry != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onRetry,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: AiMindmapPanel._muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.white,
                child: MindmapInteractiveView(
                  root: meta.tree!,
                  collapsed: _collapsed,
                  onToggle: _toggleCollapsed,
                  viewHeight: 280,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击节点可折叠/展开分支；双指缩放查看',
              style: TextStyle(
                fontSize: 12,
                color: AiMindmapPanel._muted,
                height: 1.4,
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
  });

  final AiMindmapNode root;
  final Set<String> collapsed;
  final ValueChanged<String> onToggle;
  final double? viewHeight;
  final double minScale;
  final double maxScale;

  @override
  State<MindmapInteractiveView> createState() => _MindmapInteractiveViewState();
}

class _MindmapInteractiveViewState extends State<MindmapInteractiveView> {
  final _controller = TransformationController();
  bool _initialFitDone = false;

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
        root: widget.root,
        collapsed: widget.collapsed,
        onToggle: widget.onToggle,
      ),
    );

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
            return viewer;
          },
        ),
      );
    }
    return viewer;
  }
}

/// 全屏预览思维导图
void showMindmapFullscreen(
  BuildContext context, {
  required AiMindmapNode root,
  String? sourceTitle,
  Set<String>? initialCollapsed,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => MindmapFullscreenPage(
        root: root,
        sourceTitle: sourceTitle,
        initialCollapsed: initialCollapsed,
      ),
    ),
  );
}

class MindmapFullscreenPage extends StatefulWidget {
  const MindmapFullscreenPage({
    super.key,
    required this.root,
    this.sourceTitle,
    this.initialCollapsed,
  });

  final AiMindmapNode root;
  final String? sourceTitle;
  final Set<String>? initialCollapsed;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  State<MindmapFullscreenPage> createState() => _MindmapFullscreenPageState();
}

class _MindmapFullscreenPageState extends State<MindmapFullscreenPage> {
  late final Set<String> _collapsed;
  bool _landscape = false;
  bool _sharing = false;

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

  Future<void> _shareMindmap() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await shareMindmapImage(
        context: context,
        root: widget.root,
        sourceTitle: widget.sourceTitle,
      );
    } catch (_) {
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
            tooltip: '分享',
            icon: _sharing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MindmapFullscreenPage._muted.withValues(alpha: 0.85),
                    ),
                  )
                : const Icon(
                    Icons.ios_share_rounded,
                    color: MindmapFullscreenPage._muted,
                  ),
            onPressed: _sharing ? null : _shareMindmap,
          ),
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
    required this.root,
    required this.collapsed,
    required this.onToggle,
  });

  final AiMindmapNode root;
  final Set<String> collapsed;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final layout = MindmapLayout.compute(root, collapsed);
    return Listener(
      onPointerUp: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(event.position);
        for (final node in layout.nodes.values) {
          if (node.rect.contains(local)) {
            onToggle(node.path);
            break;
          }
        }
      },
      child: SizedBox(
        width: layout.width,
        height: layout.height,
        child: CustomPaint(
          size: Size(layout.width, layout.height),
          painter: MindmapPainter(layout: layout),
        ),
      ),
    );
  }
}

class _MindmapLoadingCard extends StatelessWidget {
  const _MindmapLoadingCard();

  @override
  Widget build(BuildContext context) {
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
              const Expanded(
                child: Text(
                  '正在生成思维导图…',
                  style: TextStyle(
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
            '完成后可缩放查看结构',
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AiMindmapPanel._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
