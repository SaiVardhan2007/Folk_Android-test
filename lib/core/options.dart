import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'api.dart';
import 'cache.dart';
import 'models.dart';
import 'widgets.dart';

/// Every dropdown list (College / Company, Branch, Skill, Interest). Saved copy first, then fresh (works offline).
final optionsProvider = StreamProvider<OptionLists>((ref) {
  final user = ref.watch(authProvider).value;
  if (user == null) return Stream.error(ApiException('Not signed in'));
  return cachedGet(ref, '/options', OptionLists.fromJson);
});

/// The small "Add" next to a dropdown: adds [title] to [list] for everyone and returns it with its ID.
/// If the same value already exists (differing only in case or spacing) the existing one is returned instead.
/// Shows the error and returns null when it fails (for example, no internet).
Future<Opt?> addOption(BuildContext context, WidgetRef ref, OptionList list, String title) async {
  try {
    final r = await ref.read(apiProvider).post('/options/${list.name}', body: {'title': title});
    ref.invalidate(optionsProvider);
    return Opt.fromJson(r);
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.isNetwork ? 'No internet. Connect and tap Add again.' : e.message, error: true);
    return null;
  }
}
