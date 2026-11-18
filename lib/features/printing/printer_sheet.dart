import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/widgets.dart';
import 'printer_service.dart';

/// Lets the user pick a paired Bluetooth printer or a plugged-in USB printer and connects to it.
/// Returns true when a printer is connected.
Future<bool> showPrinterPicker(BuildContext context, PrinterService printer) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PrinterPicker(printer: printer),
  );
  return ok == true;
}

/// Connects without asking when the last printer is reachable; otherwise opens the picker.
Future<bool> ensurePrinter(BuildContext context, PrinterService printer) async {
  if (await printer.reconnectLast()) return true;
  if (!context.mounted) return false;
  return showPrinterPicker(context, printer);
}

class _PrinterPicker extends StatefulWidget {
  const _PrinterPicker({required this.printer});
  final PrinterService printer;
  @override
  State<_PrinterPicker> createState() => _PrinterPickerState();
}

class _PrinterPickerState extends State<_PrinterPicker> {
  List<PrinterDevice> _bt = const [], _usb = const [];
  String? _btError;
  bool _loading = true, _connecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final perm = await widget.printer.bluetoothPermission();
    List<PrinterDevice> bt = const [], usb = const [];
    String? err;
    if (perm == 'blocked') {
      err = 'Bluetooth permission is blocked. Allow it in the app settings.';
    } else if (perm == 'denied') {
      err = 'Bluetooth permission is needed to find the printer.';
    } else {
      try {
        bt = await widget.printer.bluetoothDevices();
      } on PrinterException catch (e) {
        err = e.message;
      }
    }
    try {
      usb = await widget.printer.usbDevices();
    } on PrinterException {
      // no USB support: just show none
    }
    if (!mounted) return;
    setState(() {
      _bt = bt;
      _usb = usb;
      _btError = err;
      _loading = false;
    });
  }

  Future<void> _connect(PrinterDevice d) async {
    setState(() => _connecting = true);
    try {
      await widget.printer.connect(d);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PrinterException catch (e) {
      if (!mounted) return;
      setState(() => _connecting = false);
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget tile(PrinterDevice d) => ListTile(
      leading: Icon(d.kind == PrinterKind.usb ? Icons.usb_rounded : Icons.bluetooth_rounded),
      title: Text(d.name),
      subtitle: Text(d.kind == PrinterKind.usb ? 'USB cable' : d.id),
      enabled: !_connecting,
      onTap: () => _connect(d),
    );
    return SheetBody(
      children: [
        Text('Connect a printer', style: text.titleLarge),
        const SizedBox(height: kGapS),
        Text(
          'Switch the printer on. For Bluetooth, pair it once in the phone\'s Bluetooth settings first. For USB, plug it in with an OTG cable.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: kGapM),
        if (_loading || _connecting)
          const Padding(
            padding: EdgeInsets.all(kGapXL),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_btError != null)
            StatusBanner(
              icon: Icons.bluetooth_disabled_rounded,
              text: _btError!,
              action: TextButton(onPressed: widget.printer.openAppSettings, child: const Text('Settings')),
            ),
          if (_usb.isEmpty && _bt.isEmpty && _btError == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: kGapM),
              child: Text('No paired Bluetooth printer or USB printer found.', style: text.bodyLarge),
            ),
          for (final d in _usb) tile(d),
          for (final d in _bt) tile(d),
          const SizedBox(height: kGapS),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Search again')),
        ],
      ],
    );
  }
}
