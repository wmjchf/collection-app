import 'package:flutter/material.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/shell/main_shell.dart';

class SuperCollectionApp extends StatelessWidget {
  const SuperCollectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '超级收藏夹',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FED),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _auth = AuthRepository();
  late Future<AuthSession?> _future;

  @override
  void initState() {
    super.initState();
    _future = _auth.readSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthSession?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data != null) {
          return const MainShell();
        }
        return const LoginPage();
      },
    );
  }
}
