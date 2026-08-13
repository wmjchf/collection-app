import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/parse_progress_banner.dart';
import 'package:super_collection/core/ui/parse_progress_controller.dart';
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
  final _parseProgress = ParseProgressController.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              HomePage(isActive: _index == 0),
              CollectionPage(isActive: _index == 1),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 10,
            child: ParseProgressBanner(controller: _parseProgress),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _index,
        onChanged: (value) => setState(() => _index = value),
      ),
    );
  }
}
