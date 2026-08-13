import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/folder_models.dart';
import 'package:super_collection/features/collection/folders_repository.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

Future<CollectionItem?> showReadingFolderSheet(
  BuildContext context, {
  required int itemId,
  int? currentFolderId,
}) {
  return showModalBottomSheet<CollectionItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) => _ReadingFolderSheet(
      itemId: itemId,
      currentFolderId: currentFolderId,
    ),
  );
}

class _ReadingFolderSheet extends StatefulWidget {
  const _ReadingFolderSheet({
    required this.itemId,
    this.currentFolderId,
  });

  final int itemId;
  final int? currentFolderId;

  @override
  State<_ReadingFolderSheet> createState() => _ReadingFolderSheetState();
}

class _ReadingFolderSheetState extends State<_ReadingFolderSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);
  static const _rowBg = Color(0xFFF5F7FA);

  final _foldersRepo = FoldersRepository();
  final _itemsRepo = ItemsRepository();
  List<Folder> _folders = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await _foldersRepo.listFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _select(Folder folder) async {
    if (_saving) return;
    if (folder.id == widget.currentFolderId) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final item = await _itemsRepo.moveToFolder(widget.itemId, folder.id);
      if (!mounted) return;
      Navigator.pop(context, item);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移动失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _handle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        '移动到收藏夹',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          '关闭',
                          style: TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(_error!, style: const TextStyle(color: _muted)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _folders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final folder = _folders[index];
                          final selected =
                              folder.id == widget.currentFolderId;
                          return InkWell(
                            onTap: _saving ? null : () => _select(folder),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFE5EDFF)
                                    : _rowBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: 20,
                                    color: selected ? _blue : _text,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      folder.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected ? _blue : _text,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check,
                                      size: 18,
                                      color: _blue,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
