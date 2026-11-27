import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'person_form.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _key = GlobalKey<FormState>();
  final _mob = TextEditingController();
  final _form = PersonFormController();
  bool _busy = false;

  @override
  void dispose() {
    _mob.dispose();
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final mob = normalizeMobile(_mob.text)!;
      await ref.read(apiProvider).post('/people', body: {..._form.toJson(), 'mob': mob, 'event_code': ref.read(selectedEventProvider) ?? ''});
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, 'Registered ${_form.name.text.trim()}');
      _mob.clear();
      _form.clear();
      _key.currentState!.reset();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootstrapProvider).value;
    return Form(
      key: _key,
      child: PageBody(
        children: [
          Text('Register a new attendee', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const EventPicker(label: 'Registering for event'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _mob,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')), LengthLimitingTextInputFormatter(15)],
            decoration: const InputDecoration(labelText: 'Mobile number *', prefixIcon: Icon(Icons.phone_outlined), prefixText: '+91  '),
            validator: (v) => normalizeMobile(v ?? '') == null ? 'Enter a valid 10-digit mobile number' : null,
          ),
          const SizedBox(height: 10),
          PersonFields(form: _form, boot: boot),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3))
                : const Icon(Icons.person_add_alt_1),
            label: const Text('Register'),
          ),
        ],
      ),
    );
  }
}
