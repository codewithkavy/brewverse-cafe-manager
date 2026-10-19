import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import '../services/thermal_printer_service.dart';
import '../theme/app_theme.dart';

class ThermalPrinterDialog extends StatefulWidget {
  const ThermalPrinterDialog({
    required this.cafeName,
    required this.billNumber,
    required this.orderType,
    required this.items,
    required this.total,
    this.discount = 0,
    super.key,
  });

  final String cafeName;
  final String billNumber;
  final String orderType;
  final List<Map<String, dynamic>> items;
  final double total;
  final double discount;

  @override
  State<ThermalPrinterDialog> createState() => _ThermalPrinterDialogState();
}

class _ThermalPrinterDialogState extends State<ThermalPrinterDialog> {
  static const Color _panel = AppTheme.card;
  static const Color _card = AppTheme.softGreen;
  static const Color _caramel = AppTheme.emerald;
  static const Color _cream = AppTheme.ink;
  static const Color _muted = AppTheme.mutedInk;

  final FlutterThermalPrinter _plugin = FlutterThermalPrinter.instance;
  final ThermalPrinterService _service = ThermalPrinterService();
  final List<Printer> _printers = [];
  StreamSubscription<List<Printer>>? _subscription;
  Timer? _scanTimer;
  bool _scanning = false;
  String? _error;
  String? _printingId;

  @override
  void initState() {
    super.initState();
    _plugin.bleConfig = const BleConfig(
      connectionStabilizationDelay: Duration(seconds: 2),
    );
    _subscription = _plugin.devicesStream.listen(
      (devices) {
        if (!mounted) return;
        setState(() {
          _printers
            ..clear()
            ..addAll(devices.where(
              (device) =>
                  device.connectionType == ConnectionType.BLE &&
                  (device.name?.trim().isNotEmpty ?? false),
            ));
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = error.toString());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning || !mounted) return;
    setState(() {
      _scanning = true;
      _error = null;
      _printers.clear();
    });
    try {
      await _plugin.getPrinters(
        connectionTypes: const [ConnectionType.BLE],
        androidUsesFineLocation: false,
      );
      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 8), () async {
        try {
          await _plugin.stopScan();
        } catch (error) {
          if (mounted) {
            setState(() => _error = 'Could not stop printer scan: $error');
          }
        } finally {
          if (mounted) setState(() => _scanning = false);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'Could not scan for Bluetooth printers: $error';
        });
      }
    }
  }

  Future<void> _print(Printer printer) async {
    if (_printingId != null) return;
    setState(() {
      _printingId = printer.uniqueId;
      _error = null;
    });
    var connectedHere = false;
    try {
      if (!(printer.isConnected ?? false)) {
        connectedHere = await _plugin.connect(printer);
        if (!connectedHere) {
          throw StateError('The printer did not accept the connection.');
        }
      }
      await _service.printReceipt(
        device: printer,
        cafeName: widget.cafeName,
        billNumber: widget.billNumber,
        orderType: widget.orderType,
        items: widget.items,
        total: widget.total,
        discount: widget.discount,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Receipt sent to the printer.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not print receipt: $error');
    } finally {
      if (connectedHere) {
        try {
          await _plugin.disconnect(printer);
        } catch (_) {
          // Printing status is already reported; disconnect failures are non-fatal.
        }
      }
      if (mounted) setState(() => _printingId = null);
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_plugin.stopScan().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.emeraldLight,
      child: AlertDialog(
        backgroundColor: _panel,
        title: Row(
          children: [
            const Expanded(
              child: Text('Bluetooth receipt printer',
                  style: TextStyle(color: _cream)),
            ),
            IconButton(
              tooltip: 'Scan again',
              onPressed: _scanning || _printingId != null ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _caramel),
                    )
                  : const Icon(Icons.refresh_rounded, color: _caramel),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          height: 360,
          child: Column(
            children: [
              const Text(
                'Select a BLE thermal printer. Keep the printer powered on and nearby.',
                style: TextStyle(color: _muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: Colors.orangeAccent)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _printers.isEmpty
                    ? Center(
                        child: Text(
                          _scanning
                              ? 'Scanning for nearby printers…'
                              : 'No BLE printers found. Check Bluetooth and scan again.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _printers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final printer = _printers[index];
                          final busy = _printingId == printer.uniqueId;
                          return Card(
                            color: _card,
                            child: ListTile(
                              leading: const Icon(Icons.print_rounded,
                                  color: _caramel),
                              title: Text(
                                printer.name ?? 'Thermal printer',
                                style: const TextStyle(color: _cream),
                              ),
                              subtitle: Text(
                                printer.isConnected == true
                                    ? 'Connected'
                                    : 'BLE printer',
                                style: const TextStyle(color: _muted),
                              ),
                              trailing: busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.print_outlined,
                                      color: _caramel),
                              onTap: _printingId == null
                                  ? () => _print(printer)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed:
                _printingId == null ? () => Navigator.of(context).pop() : null,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
