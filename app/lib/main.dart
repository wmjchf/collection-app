import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/app.dart';
import 'package:super_collection/core/network/api_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.deferFirstFrame();
  unawaited(ApiClient.warmup());
  runApp(const SuperCollectionApp());
}
