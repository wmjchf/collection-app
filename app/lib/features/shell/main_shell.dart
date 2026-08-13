import 'package:flutter/material.dart';
import 'package:super_collection/features/collection/collection_page.dart';
import 'package:super_collection/features/home/home_page.dart';
import 'package:super_collection/features/shell/app_bottom_nav_bar.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(isActive: _index == 0),
          CollectionPage(isActive: _index == 1),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _index,
        onChanged: (value) => setState(() => _index = value),
      ),
    );
  }
}
