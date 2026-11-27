import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import 'auth_controller.dart';

enum _Mode { signIn, signUp }

/// Exactly six digits standing on their own (the app hash at the end of the SMS can also contain digits).
const _codeMatcher = r'(?<!\d)\d{6}(?!\d)';

/// Sign in with the mobile number and an SMS code. There are no passwords.
/// The code is read from the SMS by itself: with no prompt when the SMS carries the app hash (SMS Retriever API),
/// otherwise Android asks once to allow reading that one SMS (SMS User Consent API). Typing it always works too.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _mob = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _sms = SmartAuth.instance;
  _Mode _mode = _Mode.signIn;
  bool _codeStep = false, _busy = false;
  String _level = '', _gender = '', _appHash = '';
  String? _error, _info;
  int _wait = 0, _attempt = 0;
  Timer? _ticker;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_android) unawaited(_loadAppHash());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopListening();
    _mob.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadAppHash() async {
    final res = await _sms.getAppSignature();
    final h = res.data ?? '';
    if (RegExp(r'^[A-Za-z0-9+/]{11}$').hasMatch(h)) _appHash = h;
  }

  void _stopListening() {
    if (!_android) return;
    _sms.removeSmsRetrieverApiListener();
    _sms.removeUserConsentApiListener();
  }

  /// Waits for the SMS and signs in with its code. Autofill is a convenience; typing the code always works.
  Future<void> _listen({required bool noPrompt}) async {
    if (!_android) return;
    final attempt = _attempt;
    final res = noPrompt ? await _sms.getSmsWithRetrieverApi(matcher: _codeMatcher) : await _sms.getSmsWithUserConsentApi(matcher: _codeMatcher);
    final code = res.data?.code;
    if (!mounted || attempt != _attempt || code == null || code.length != 6) return;
    _code.text = code;
    unawaited(_verify()); // if the SMS beat the "send" reply, _afterSend signs in instead
  }

  void _startWait() {
    _ticker?.cancel();
    setState(() => _wait = kOtpResendSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) {
        t.cancel();
        if (mounted) setState(() => _wait = 0);
      } else {
        setState(() => _wait--);
      }
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.data['no_account'] == true) _mode = _Mode.signUp;
          if (e.data['has_account'] == true) _mode = _Mode.signIn;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Texts the code and moves to the code step.
  Future<void> _sendCode() async {
    final mob = normalizeMobile(_mob.text)!;
    _attempt++;
    _code.clear();
    // Listen before the SMS is sent so a fast SMS is not missed. The no-prompt listener never shows anything,
    // so it is safe to start it even if this SMS turns out not to carry the app hash.
    _stopListening();
    final retriever = _listen(noPrompt: true);
    final autoRead = await ref.read(authProvider.notifier).sendOtp(mob, appHash: _appHash);
    if (!mounted) return;
    if (!autoRead) {
      _stopListening(); // ends the no-prompt wait; fall back to the one-tap "Allow" prompt
      await retriever;
      unawaited(_listen(noPrompt: false));
    }
    setState(() => _codeStep = true);
    _startWait();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_codeStep) return _verify();
    setState(() => _info = null);
    await _run(() async {
      if (_mode == _Mode.signUp) {
        final res = await ref
            .read(authProvider.notifier)
            .signup(mob: normalizeMobile(_mob.text)!, name: _name.text.trim(), level: _level, gender: _gender);
        if (!mounted) return;
        setState(() {
          _info = res.message;
          _mode = _Mode.signIn;
        });
        if (!res.approved) return;
      }
      await _sendCode();
    });
    _afterSend();
  }

  Future<void> _resend() async {
    await _run(_sendCode);
    _afterSend();
  }

  /// The SMS can be read before the "send" reply arrives; sign in with it now.
  void _afterSend() {
    if (mounted && _codeStep && _code.text.length == 6) unawaited(_verify());
  }

  Future<void> _verify() async {
    if (_busy || _code.text.trim().length != 6) return;
    // On success the user is signed in and the router moves to the home screen by itself.
    await _run(() => ref.read(authProvider.notifier).verifyOtp(normalizeMobile(_mob.text)!, _code.text.trim()));
  }

  void _changeNumber() {
    _attempt++;
    _stopListening();
    _ticker?.cancel();
    setState(() {
      _codeStep = false;
      _wait = 0;
      _error = null;
      _info = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final signUp = _mode == _Mode.signUp;
    final (title, hint, button) = _codeStep
        ? (
            'Enter the code',
            'We sent a 6-digit code to +91 ${normalizeMobile(_mob.text)}. It is filled in automatically when the SMS arrives.',
            'Sign in',
          )
        : signUp
        ? ('Create your account', 'Enter your name and mobile number. An admin approves new accounts, then you sign in with an SMS code.', 'Sign up')
        : ('Sign in', 'Enter your mobile number. We will send you a 6-digit code by SMS.', 'Send code');

    // Laptops and tablets: brand panel on the left, the form on the right (fields never stretch across a wide screen).
    final wide = context.windowClass == WindowClass.expanded;
    final form = Form(
      key: _form,
      child: ListView(
        shrinkWrap: wide, // lets Center place the form in the middle of its half
        padding: EdgeInsets.symmetric(horizontal: wide ? kGapXL * 2 : kPagePadding, vertical: kGapXL),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (!wide) ...[
            const Center(child: AppLogo(height: 110)),
            const SizedBox(height: kGapXL),
            Text('Hare Krishna', style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: kGapL),
          ],
          if (!_codeStep) ...[
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
          ],
          Text(title, style: text.titleLarge),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(hint, style: text.bodyMedium),
          ),
          const SizedBox(height: 16),
          FieldGrid(
            children: [
              if (!_codeStep)
                TextFormField(
                  controller: _mob,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')), LengthLimitingTextInputFormatter(15)],
                  decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_outlined), prefixText: '+91  '),
                  validator: (v) => normalizeMobile(v ?? '') == null ? 'Enter a valid 10-digit mobile number' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              if (!_codeStep && signUp)
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),
              if (!_codeStep && signUp)
                OptionDropdown(
                  label: 'Level',
                  value: _level,
                  options: const ['Folk Foundation', 'Folk Prelims'],
                  icon: Icons.school_outlined,
                  onChanged: (v) => setState(() => _level = v),
                ),
              if (!_codeStep && signUp)
                OptionDropdown(
                  label: 'Gender',
                  value: _gender,
                  options: const ['M', 'F'],
                  labelOf: (v) => v == 'M' ? 'Male' : 'Female',
                  icon: Icons.wc_outlined,
                  onChanged: (v) => setState(() => _gender = v),
                ),
              if (_codeStep)
                TextFormField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.pin_outlined)),
                  validator: (v) => (v ?? '').length == 6 ? null : 'Enter the 6-digit code',
                  onChanged: (v) {
                    if (v.length == 6) _verify();
                  },
                ),
            ],
          ),
          if (_error != null) ...[const SizedBox(height: 10), StatusBanner(icon: Icons.error_outline, text: _error!, color: context.colors.danger)],
          if (_info != null && !_codeStep) ...[
            const SizedBox(height: 10),
            StatusBanner(icon: Icons.hourglass_top_outlined, text: _info!, color: context.colors.success),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3)) : Text(button),
          ),
          if (_codeStep) ...[
            TextButton(
              onPressed: _busy || _wait > 0 ? null : _resend,
              child: Text(_wait > 0 ? 'Send the code again in $_wait s' : 'Send the code again'),
            ),
            TextButton(onPressed: _busy ? null : _changeNumber, child: const Text('Change mobile number')),
          ],
        ],
      ),
    );

    return PopScope(
      canPop: !_codeStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _changeNumber();
      },
      child: Scaffold(
        body: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: _BrandPanel()),
                  Expanded(
                    child: SafeArea(child: Center(child: form)),
                  ),
                ],
              )
            : SafeArea(child: form),
      ),
    );
  }
}

/// The left half of the sign-in page on wide screens: the brand gradient with the logo and greeting.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kBrandGradient),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(kGapXL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(height: 130),
                const SizedBox(height: kGapXL),
                Text(
                  'Hare Krishna',
                  style: text.headlineMedium?.copyWith(color: kOnBrand, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: kGapS),
                Text(
                  'FOLK Tracker: attendance, calls and follow-ups',
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: kOnBrand.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
