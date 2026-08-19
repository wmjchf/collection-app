import 'package:flutter/material.dart';
import 'package:super_collection/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.deferFirstFrame();
  runApp(const SuperCollectionApp());
}
