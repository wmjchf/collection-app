import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/app.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_orientation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.deferFirstFrame();
  unawaited(AppOrientation.applyDefault());
  unawaited(ApiClient.warmup());
  runApp(const SuperCollectionApp());
}
