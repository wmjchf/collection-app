import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/app.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.deferFirstFrame();
  await ThemeController.instance.load();
  unawaited(ApiClient.warmup());
  runApp(const SuperCollectionApp());
}
