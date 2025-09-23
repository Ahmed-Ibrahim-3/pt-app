// lib/auth_gate.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'services/firestore_sync.dart';
import 'home_page.dart';
import 'screens/sign_in_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});
  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    // Pull once on app launch (if already signed in)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_launched) return;
      _launched = true;
      await ref.read(firestoreSyncProvider).onLaunch();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Pull on every UID change
    ref.listen(authStateProvider, (prev, next) {
      final prevUid = prev?.value?.uid;
      final curUid  = next.value?.uid;
      if (prevUid == curUid) return;
      scheduleMicrotask(() {
        ref.read(firestoreSyncProvider).onAuthChange(
          previousUid: prevUid,
          currentUid: curUid,
        );
      });
    });

    final authAsync = ref.watch(authStateProvider);
    return authAsync.when(
      data: (user) => user == null ? const SignInPage() : const HomePage(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}
