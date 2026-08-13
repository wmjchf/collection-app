import 'package:flutter/material.dart';

/// 我的收藏：系统筛选 / 收藏夹 / 标签 / 其他（后续迭代实现）
class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionCard(
            children: const [
              _NavTile(icon: Icons.radio_button_unchecked, title: '未读', trailing: '无'),
              _NavTile(icon: Icons.list_alt, title: '所有', trailing: '0'),
              _NavTile(icon: Icons.today_outlined, title: '今天', trailing: '0'),
              _NavTile(icon: Icons.star_outline, title: '星标', trailing: '0'),
              _NavTile(icon: Icons.article_outlined, title: '解析', trailing: '0'),
              _NavTile(icon: Icons.highlight_outlined, title: '标注', trailing: '0'),
              _NavTile(icon: Icons.history, title: '最近阅读', trailing: '0'),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(title: '收藏夹', onAdd: () {}),
          _SectionCard(
            children: const [
              _NavTile(icon: Icons.inbox_outlined, title: '未分类', trailing: '0'),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(title: '标签', onAdd: () {}),
          _SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '暂无标签',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionHeader(title: '其他'),
          _SectionCard(
            children: const [
              _NavTile(icon: Icons.delete_outline, title: '回收站', trailing: '0'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAdd});

  final String title;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (onAdd != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 20),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trailing,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title：后续实现')),
        );
      },
    );
  }
}
