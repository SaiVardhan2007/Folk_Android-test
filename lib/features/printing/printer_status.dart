import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/auth_controller.dart';
import 'printer_service.dart';
import 'receipt_format.dart';
import 'receipt_renderer.dart';

/// How many phones are connected to a printer right now (asked once; tap the chip or mark someone to ask again, nothing polls).
final printStationsProvider = FutureProvider.autoDispose<int>((ref) async {
  final r = await ref.watch(apiProvider).get('/print/status');
  return (r['stations'] as num?)?.toInt() ?? 0;
});

/// Shows next to "Mark & Print Receipt" whether a receipt will actually print.
class PrinterStatusChip extends ConsumerWidget {
  const PrinterStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final here = ref.watch(printerHereProvider).value ?? false;
    // This phone connecting or disconnecting changes the server's count too: ask again.
    ref.listen(printerHereProvider, (_, _) => ref.invalidate(printStationsProvider));
    final others = ref.watch(printStationsProvider);
    final c = context.colors;
    final (IconData icon, String label, Color color) = here
        ? (Icons.print_rounded, 'Printer connected to this phone', c.success)
        : others.when(
            data: (n) => n > 0
                ? (Icons.print_rounded, 'Printer connected (another phone prints for you)', c.success)
                : (Icons.print_disabled_outlined, 'No printer connected. Receipts wait until a phone connects one', c.warning),
            loading: () => (Icons.print_outlined, 'Checking printer…', Theme.of(context).hintColor),
            error: (_, _) => (Icons.print_outlined, 'Printer status unknown. Tap to check again', Theme.of(context).hintColor),
          );
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => ref.invalidate(printStationsProvider),
      onLongPress: here ? () => _testPrint(context, ref) : null, // TEMPORARY: printing comparison test, remove after the test
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// TEMPORARY printing comparison (A = current slices with pauses, B = one continuous write). Prints a sample; marks nobody.
Future<void> _testPrint(BuildContext context, WidgetRef ref) async {
  final continuous = await showModalBottomSheet<bool>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Test A (current method)'), onTap: () => Navigator.pop(c, false)),
          ListTile(leading: const Icon(Icons.print_rounded), title: const Text('Test B (continuous)'), onTap: () => Navigator.pop(c, true)),
        ],
      ),
    ),
  );
  if (continuous == null) return;
  final fmt = ref.read(bootstrapProvider).value?.receipt ?? const ReceiptFormat();
  final data = ReceiptData(
    name: continuous ? 'TEST B' : 'TEST A',
    mob: '9876543210',
    event: 'Saturday Satsang',
    ts: '2026-11-21 17:45:00',
    count: 1,
    markedBy: 'Test',
    guide: 'VKGD',
    guideMobile: '9133318576',
  );
  try {
    await ref.read(printerServiceProvider).printImage(await renderReceipt(fmt, data), continuous: continuous);
    if (context.mounted) showMessage(context, continuous ? 'Test B sent.' : 'Test A sent.');
  } on PrinterException catch (e) {
    if (context.mounted) showMessage(context, 'Could not print: ${e.message}', error: true);
  }
}
