import 'package:flutter/material.dart';

/// 一级页：首页 — 未读 / 标注 / 最近阅读 三板块
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('搜索：后续实现')),
              );
            },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '添加链接',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('添加链接弹框：后续实现')),
              );
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _HomeSection(
            title: '未读',
            emptyText: '暂无未读',
          ),
          SizedBox(height: 20),
          _HomeSection(
            title: '标注',
            emptyText: '暂无标注',
          ),
          SizedBox(height: 20),
          _HomeSection(
            title: '最近阅读',
            emptyText: '暂无最近阅读',
          ),
        ],
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.emptyText,
  });

  final String title;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title · 查看更多：后续实现')),
                );
              },
              child: const Text('查看更多'),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Center(
              child: Text(
                emptyText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
