import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../shared/services/supabase_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading    = false;
  bool _obscure    = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Check connectivity first
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        setState(() => _error = 'No internet connection. Check your WiFi/mobile data.');
        return;
      }
    } catch (e) {
      print('[Login] Connectivity check failed: $e');
    }
    
    setState(() { _loading = true; _error = null; });
    try {
      print('[Login] Attempting login for ${_emailCtrl.text.trim()}...');
      final service = ref.read(supabaseServiceProvider);
      
      // Add timeout to prevent hanging indefinitely
      final res = await service.signInWithEmail(
          _emailCtrl.text.trim(), _passCtrl.text)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('Login timeout - server not responding'),
        );

      if (res.user == null) {
        print('[Login] User is null after auth');
        setState(() => _error = 'Login failed. Please try again.');
        return;
      }
      
      print('[Login] ✓ Auth successful for ${res.user!.email}');
      if (!mounted) return;

      // Try to get profile — if missing, create it then proceed
      try {
        print('[Login] Fetching profile...');
        final profile = await service.getProfile(res.user!.id)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Profile fetch timeout'),
          );
        
        print('[Login] ✓ Profile found: ${profile.role}');
        if (!mounted) return;
        if (profile.isAdmin) {
          context.go('/admin');
        } else if (profile.isEngineer) {
          context.go('/engineer');
        } else {
          context.go('/home');
        }
      } catch (profileError) {
        print('[Login] Profile fetch error: $profileError');
        print('[Login] Creating profile...');
        await service.createProfileIfMissing(
            res.user!.id, _emailCtrl.text.trim());
        print('[Login] ✓ Profile created');
        if (mounted) context.go('/home');
      }
    } catch (e) {
      print('[Login] Login error: $e');
      final msg = e.toString().toLowerCase();
      
      if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
        setState(() => _error = 'Wrong email or password.');
      } else if (msg.contains('email not confirmed')) {
        setState(() => _error =
            'Email not confirmed. Check your email or disable email confirmation in Supabase.');
      } else if (msg.contains('rate limit')) {
        setState(() => _error = 'Too many attempts. Wait 1 minute and try again.');
      } else if (msg.contains('timeout')) {
        setState(() => _error = 'Connection timeout. Server not responding.');
      } else if (msg.contains('socket') || msg.contains('connection')) {
        setState(() => _error = 'Network error. Check internet connection.\n\nURL: ${msg.split('uri=').last.split(',').first}');
      } else if (msg.contains('software caused connection abort') || msg.contains('errno = 103')) {
        setState(() => _error = 'Connection reset by server. Check Supabase credentials.');
      } else {
        setState(() => _error = 'Error: ${e.toString().split('\n').first}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.construction_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Text('FixMyRoad',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 40),
                Text('Welcome back',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Sign in to report potholes in your area.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("Don't have an account? ",
                      style: theme.textTheme.bodyMedium),
                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Sign up'),
                  ),
                ]),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/map'),
                    child: const Text('View map without signing in'),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Connecting to server...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}