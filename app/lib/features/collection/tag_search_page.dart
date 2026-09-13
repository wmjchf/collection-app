import 'package:flutter/material.dart';
import 'package:super_collection/features/search/search_page.dart';

/// 兼容旧入口：标签搜索已并入统一 [SearchPage]。
class TagSearchPage extends StatelessWidget {
  const TagSearchPage({super.key});

  @override
  Widget build(BuildContext context) => const SearchPage();
}
