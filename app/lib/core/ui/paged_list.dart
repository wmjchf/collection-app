import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 条目列表分页：与后端 limit/offset 对齐
const int kItemsPageSize = 20;

/// 距底部多少像素触发加载更多
const double kLoadMoreExtent = 320;

bool shouldLoadMore(ScrollController controller) {
  if (!controller.hasClients) return false;
  final pos = controller.position;
  if (!pos.hasPixels || !pos.hasContentDimensions) return false;
  return pos.pixels >= pos.maxScrollExtent - kLoadMoreExtent;
}

/// 首屏内容不够滚动时继续拉下一页，直到可滚或没有更多
void scheduleFillViewport({
  required ScrollController controller,
  required bool Function() hasMore,
  required bool Function() isBusy,
  required VoidCallback loadMore,
}) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (isBusy() || !hasMore()) return;
    if (!controller.hasClients) return;
    final pos = controller.position;
    if (!pos.hasContentDimensions) return;
    if (pos.maxScrollExtent <= kLoadMoreExtent) {
      loadMore();
    }
  });
}

Widget pagedListFooter({
  required bool loadingMore,
  required bool hasMore,
  required bool isEmpty,
}) {
  if (isEmpty) return const SizedBox.shrink();
  if (loadingMore) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
  if (!hasMore) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          '没有更多了',
          style: TextStyle(fontSize: 12, color: Color(0xFF737A85)),
        ),
      ),
    );
  }
  return const SizedBox(height: 8);
}
