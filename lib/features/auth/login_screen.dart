import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import 'auth_controller.dart';
import '../../core/layout.dart';

enum _Mode { signIn, signUp, reset }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _mob = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  _Mode _mode = _Mode.signIn;
  String _level = '', _gender = '';
  bool _hide = true, _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _mob.dispose();
    _pass.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(authProvider.notifier);
    final mob = normalizeMobile(_mob.text)!;
    try {
      switch (_mode) {
        case _Mode.signIn:
          await auth.login(mob, _pass.text);
        case _Mode.signUp:
          final msg = await auth.signup(mob: mob, password: _pass.text, name: _name.text.trim(), level: _level, gender: _gender);
          if (msg != null && mounted) {
            setState(() {
              _info = msg;
              _mode = _Mode.signIn;
              _pass.clear();
            });
          }
        case _Mode.reset:
          await auth.activate(mob, _code.text.trim(), _pass.text);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.data['needs_code'] == true) _mode = _Mode.reset;
          if (e.data['no_password'] == true) _mode = _Mode.signUp;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final title = switch (_mode) {
      _Mode.signIn => 'Sign in',
      _Mode.signUp => 'Create your account',
      _Mode.reset => 'Forgot password',
    };
    final button = switch (_mode) {
      _Mode.signIn => 'Sign in',
      _Mode.signUp => 'Sign up',
      _Mode.reset => 'Set new password',
    };

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(kPagePadding, 24, kPagePadding, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Center(child: AppLogo(height: 110)),
              const SizedBox(height: 24),
              Text('Hare Krishna', style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (_mode != _Mode.reset)
                SegmentedButton<_Mode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Mode.signIn, label: Text('Sign in')),
                    ButtonSegment(value: _Mode.signUp, label: Text('Sign up')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    _error = null;
                    _info = null;
                  }),
                ),
              const SizedBox(height: 20),
              Text(title, style: text.titleLarge),
              if (_mode == _Mode.signUp)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Enter your name, mobile number and a password. An admin approves new accounts before you can sign in.',
                    style: text.bodyMedium,
                  ),
                ),
              if (_mode == _Mode.reset)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Ask an admin for a 6-digit code, then enter it with your mobile number and choose a new password.',
                    style: text.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
              FieldGrid(
                children: [
                  TextFormField(
                    controller: _mob,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.username],
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')), LengthLimitingTextInputFormatter(15)],
                    decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined), prefixText: '+91  '),
                    validator: (v) => normalizeMobile(v ?? '') == null ? 'Enter a valid 10-digit mobile number' : null,
                  ),
                  if (_mode == _Mode.reset)
                    TextFormField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.pin_outlined)),
                      validator: (v) => (v ?? '').length == 6 ? null : 'Enter the 6-digit code',
                    ),
                  if (_mode == _Mode.signUp)
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                    ),
                  if (_mode == _Mode.signUp)
                    OptionDropdown(
                      label: 'Level',
                      value: _level,
                      options: const ['Folk Foundation', 'Folk Prelims'],
                      icon: Icons.school_outlined,
                      onChanged: (v) => setState(() => _level = v),
                    ),
                  if (_mode == _Mode.signUp)
                    OptionDropdown(
                      label: 'Gender',
                      value: _gender,
                      options: const ['M', 'F'],
                      labelOf: (v) => v == 'M' ? 'Male' : 'Female',
                      icon: Icons.wc_outlined,
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                  TextFormField(
                    controller: _pass,
                    obscureText: _hide,
                    autofillHints: [_mode == _Mode.signIn ? AutofillHints.password : AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: _mode == _Mode.signIn ? 'Password' : 'New password ($kMinPasswordLength+ characters)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Enter your password';
                      if (_mode != _Mode.signIn && v!.length < kMinPasswordLength) return 'At least $kMinPasswordLength characters';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
              ),
              if (_mode == _Mode.signIn)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _mode = _Mode.reset;
                      _error = null;
                      _info = null;
                    }),
                    child: const Text('Forgot password?'),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                StatusBanner(icon: Icons.error_outline, text: _error!, color: context.colors.danger),
              ],
              if (_info != null) ...[
                const SizedBox(height: 14),
                StatusBanner(icon: Icons.hourglass_top_outlined, text: _info!, color: context.colors.success),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3)) : Text(button),
              ),
              if (_mode == _Mode.reset)
                TextButton(
                  onPressed: () => setState(() {
                    _mode = _Mode.signIn;
                    _error = null;
                  }),
                  child: const Text('Back to sign in'),
                ),
              const SizedBox(height: 14),
              Text(
                'Your password is stored only as a secure hash. Admins can reset it but can never see it.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
