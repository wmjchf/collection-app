import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 列表页批量删除底栏
class ItemsBatchDeleteBar extends StatelessWidget {
  const ItemsBatchDeleteBar({
    super.key,
    required this.selectedCount,
    required this.busy,
    required this.onDelete,
  });

  final int selectedCount;
  final bool busy;
  final VoidCallback onDelete;

  static const _danger = Color(0xFFBF3333);

  @override
  Widget build(BuildContext context) {
    final enabled = selectedCount > 0 && !busy;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? onDelete : null,
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              disabledBackgroundColor: _danger.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    selectedCount > 0 ? '删除 ($selectedCount)' : '删除',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 多选态顶栏右侧：全选 / 取消全选
Widget itemsBatchSelectAllAction({
  required bool allSelected,
  required VoidCallback? onPressed,
}) {
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF1F242E),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(
      allSelected ? '取消全选' : '全选',
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
  );
}

/// 普通态顶栏「选择」
Widget itemsBatchEnterSelectAction({required VoidCallback? onPressed}) {
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF1F242E),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: const Text(
      '选择',
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
  );
}

/// 多选态顶栏「取消」
Widget itemsBatchCancelSelectAction({required VoidCallback onPressed}) {
  return TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF1F242E),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: const Text(
      '取消',
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
    ),
  );
}

PreferredSizeWidget itemsBatchSelectAppBar({
  required int selectedCount,
  required bool allSelected,
  required VoidCallback onCancel,
  required VoidCallback onToggleSelectAll,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    leadingWidth: 88,
    leading: itemsBatchCancelSelectAction(onPressed: onCancel),
    title: Text(
      '已选 $selectedCount',
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1F242E),
      ),
    ),
    actions: [
      itemsBatchSelectAllAction(
        allSelected: allSelected,
        onPressed: onToggleSelectAll,
      ),
    ],
  );
}

Future<Set<int>?> confirmAndBatchDeleteItems({
  required BuildContext context,
  required ItemsRepository repo,
  required Set<int> ids,
}) async {
  if (ids.isEmpty) return null;
  final confirmed = await showAppConfirmDialog(
    context,
    title: '删除选中的 ${ids.length} 条？',
    message: '删除后无法恢复。',
    confirmLabel: '删除',
  );
  if (confirmed != true) return null;
  if (!context.mounted) return null;

  try {
    final result = await repo.deleteItems(ids.toList());
    if (!context.mounted) return null;
    if (result.deletedIds.isEmpty) {
      final msg = result.skippedGuideIds.isNotEmpty
          ? '使用指引不可删除'
          : '没有可删除的条目';
      AppToast.show(context, msg);
      return const <int>{};
    }
    var msg = '已删除 ${result.deletedIds.length} 条';
    if (result.skippedGuideIds.isNotEmpty) {
      msg += '（使用指引已跳过）';
    }
    AppToast.show(context, msg);
    return result.deletedIds.toSet();
  } on ApiException catch (e) {
    if (context.mounted) AppToast.show(context, e.message);
    return null;
  } catch (_) {
    if (context.mounted) AppToast.show(context, '删除失败');
    return null;
  }
}
