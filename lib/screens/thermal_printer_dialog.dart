import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import '../services/thermal_printer_service.dart';
import '../services/bluetooth_receipt_transport.dart';
import '../services/printer_settings_store.dart';
import '../theme/app_theme.dart';

class ThermalPrinterDialog extends StatefulWidget {
  const ThermalPrinterDialog({
    required this.cafeName,
    required this.billNumber,
    required this.orderType,
    required this.items,
    required this.total,
    this.discount = 0,
    this.cafeId,
    this.settingsStore,
    this.issuedAt,
    this.transactionStatus,
    this.isReprint = false,
    super.key,
  }) : settingsOnly = false;

  const ThermalPrinterDialog.settings({
    required this.cafeId,
    this.settingsStore,
    super.key,
  })  : settingsOnly = true,
        cafeName = '',
        billNumber = '',
        orderType = 'dineIn',
        items = const [],
        total = 0,
        discount = 0,
        issuedAt = null,
        transactionStatus = null,
        isReprint = false;

  final String cafeName;
  final String billNumber;
  final String orderType;
  final List<Map<String, dynamic>> items;
  final double total;
  final double discount;
  final String? cafeId;
  final bool settingsOnly;
  final PrinterSettingsStore? settingsStore;
  final DateTime? issuedAt;
  final String? transactionStatus;
  final bool isReprint;

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
  final List<Printer> _classicPrinters = [];
  ReceiptEncoding _encoding = ReceiptEncoding.ascii;
  int _feedLines = 3;
  bool _cut = true;
  ReceiptTransport _transportOf(Printer p) =>
      p.connectionType == ConnectionType.BLE
          ? ReceiptTransport.ble
          : ReceiptTransport.classic;
  String? _error;
  String? _printingId;
  late final PrinterSettingsStore _settingsStore;
  ReceiptPrinterSettings? _savedSettings;
  ReceiptPaperWidth _paperWidth = ReceiptPaperWidth.mm58;
  bool _rememberPrinter = true;
  bool _autoPrint = true;
  bool _loadingSettings = true;

  List<Printer> get _availablePrinters {
    final saved = _savedSettings;
    return [
      ..._printers,
      ..._classicPrinters,
      if (saved != null &&
          ![..._printers, ..._classicPrinters].any((printer) =>
              printer.address == saved.address &&
              _transportOf(printer) == saved.transport))
        Printer(
          address: saved.address,
          name: saved.name,
          connectionType: saved.transport == ReceiptTransport.ble
              ? ConnectionType.BLE
              : null,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _settingsStore =
        widget.settingsStore ?? SharedPreferencesPrinterSettingsStore();
    unawaited(_loadSettings());
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

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsStore.load(widget.cafeId);
      if (!mounted) return;
      setState(() {
        _savedSettings = settings;
        _paperWidth = settings?.paperWidth ?? ReceiptPaperWidth.mm58;
        _autoPrint = settings?.autoPrint ?? true;
        _encoding = settings?.encoding ?? ReceiptEncoding.ascii;
        _feedLines = settings?.feedLines ?? 3;
        _cut = settings?.cut ?? true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load printer: $error');
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _scan() async {
    if (_scanning || !mounted) return;
    setState(() {
      _scanning = true;
      _error = null;
      _printers.clear();
    });
    try {
      await BluetoothReceiptPrinterTransport.sharedQueue.run(() async {
        if (!mounted) return;
        try {
          final classic = await ClassicPrinterBridge().discover();
          if (mounted) {
            setState(() {
              _classicPrinters.clear();
              _classicPrinters.addAll(classic
                  .map((p) => Printer(address: p.address, name: p.name)));
            });
          }
        } catch (error) {
          if (mounted) setState(() => _error = 'Classic discovery: $error');
        }
        if (!mounted) return;
        await _plugin.getPrinters(
          connectionTypes: const [ConnectionType.BLE],
          androidUsesFineLocation: false,
        );
      });
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

  Future<void> _print(Printer printer, {bool testReceipt = false}) async {
    if (_printingId != null || _loadingSettings) return;
    setState(() {
      _printingId = '${_transportOf(printer).name}:${printer.address}';
      _error = null;
    });
    try {
      final settings = ReceiptPrinterSettings(
          address: printer.address!,
          name: printer.name ?? 'Printer',
          transport: _transportOf(printer),
          paperWidth: _paperWidth,
          encoding: _encoding,
          feedLines: _feedLines,
          cut: _cut,
          autoPrint: _autoPrint);
      if (!widget.settingsOnly || testReceipt) {
        final bytes = await _service.buildReceiptBytes(
            cafeName: testReceipt ? 'BREWVERSE PRINT TEST' : widget.cafeName,
            billNumber: testReceipt ? 'TEST - NO SALE' : widget.billNumber,
            orderType: testReceipt ? 'takeaway' : widget.orderType,
            items: testReceipt
                ? [
                    {
                      'name': 'Test receipt - verify alignment and paper feed',
                      'quantity': 1,
                      'unitPrice': 1,
                      'lineTotal': 1
                    }
                  ]
                : widget.items,
            total: testReceipt ? 1 : widget.total,
            discount: testReceipt ? 0 : widget.discount,
            paperWidth: _paperWidth,
            encoding: _encoding,
            feedLines: _feedLines,
            cut: _cut,
            issuedAt: widget.issuedAt,
            transactionStatus: widget.transactionStatus,
            isReprint: !testReceipt && widget.isReprint);
        await BluetoothReceiptPrinterTransport().send(settings, bytes);
      }
      if ((_rememberPrinter || widget.settingsOnly) && !testReceipt) {
        await _settingsStore.save(widget.cafeId, settings);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (!testReceipt) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
          content: Text(testReceipt
              ? 'Test bytes sent. Verify the printed paper.'
              : widget.settingsOnly
                  ? 'Printer saved. Use Print Test Receipt to verify compatibility.'
                  : 'Receipt bytes sent. Paper output is not confirmed.')));
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Receipt delivery uncertain. Check paper before retrying. Sale unchanged. $error');
      }
    } finally {
      if (mounted) {
        setState(() => _printingId = null);
      }
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
      child: PopScope(
        canPop: _printingId == null,
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
            height: 560,
            child: SingleChildScrollView(
                child: Column(
              children: [
                const Text(
                  'BLE discoveries and paired Classic candidates. Pair new Classic devices in Android Settings. Test before use.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ReceiptPaperWidth>(
                  isExpanded: true,
                  initialValue: _paperWidth,
                  key: ValueKey(_paperWidth),
                  decoration: const InputDecoration(labelText: 'Paper width'),
                  items: ReceiptPaperWidth.values
                      .map((width) => DropdownMenuItem(
                            value: width,
                            child: Text('${width.millimeters} mm'),
                          ))
                      .toList(growable: false),
                  onChanged: _printingId == null && !_loadingSettings
                      ? (value) => setState(() => _paperWidth = value!)
                      : null,
                ),
                Row(children: [
                  Expanded(
                      child: DropdownButtonFormField<ReceiptEncoding>(
                          isExpanded: true,
                          initialValue: _encoding,
                          key: ValueKey(_encoding),
                          decoration:
                              const InputDecoration(labelText: 'Text profile'),
                          items: const [
                            DropdownMenuItem(
                                value: ReceiptEncoding.ascii,
                                child: Text('ASCII (safe)')),
                            DropdownMenuItem(
                                value: ReceiptEncoding.cp1252,
                                child: Text('CP1252 Latin (test)')),
                          ],
                          onChanged: _printingId == null
                              ? (v) => setState(() => _encoding = v!)
                              : null)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: _feedLines,
                          key: ValueKey(_feedLines),
                          decoration:
                              const InputDecoration(labelText: 'Feed lines'),
                          items: List.generate(
                              11,
                              (i) => DropdownMenuItem(
                                  value: i, child: Text('$i'))),
                          onChanged: _printingId == null
                              ? (v) => setState(() => _feedLines = v!)
                              : null)),
                ]),
                SwitchListTile(
                    dense: true,
                    title: const Text('Send cut command'),
                    value: _cut,
                    onChanged: _printingId == null
                        ? (v) => setState(() => _cut = v)
                        : null),
                if (!widget.settingsOnly)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remember printer for this café'),
                    value: _rememberPrinter,
                    onChanged: _printingId == null
                        ? (value) => setState(() => _rememberPrinter = value!)
                        : null,
                  ),
                if (_rememberPrinter || widget.settingsOnly)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-print after checkout'),
                    value: _autoPrint,
                    onChanged: _printingId == null
                        ? (value) => setState(() => _autoPrint = value)
                        : null,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(color: Colors.orangeAccent)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: _availablePrinters.isEmpty
                      ? Center(
                          child: Text(
                            _scanning
                                ? 'Scanning for nearby printers…'
                                : 'No candidates found. Pair Classic printers in Settings or scan for BLE.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _muted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _availablePrinters.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final printer = _availablePrinters[index];
                            final busy = _printingId ==
                                '${_transportOf(printer).name}:${printer.address}';
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
                                      : (_transportOf(printer) ==
                                              ReceiptTransport.ble
                                          ? 'BLE candidate'
                                          : 'Classic SPP candidate'),
                                  style: const TextStyle(color: _muted),
                                ),
                                trailing: busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                            IconButton(
                                                tooltip: 'Print Test Receipt',
                                                onPressed: _printingId == null
                                                    ? () => _print(printer,
                                                        testReceipt: true)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.receipt_long)),
                                            Icon(
                                                widget.settingsOnly
                                                    ? Icons.save_outlined
                                                    : Icons.print_outlined,
                                                color: _caramel)
                                          ]),
                                onTap: _printingId == null && !_loadingSettings
                                    ? () => _print(printer)
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            )),
          ),
          actions: [
            if (_savedSettings != null)
              TextButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: const Text('Print Test Receipt'),
                onPressed: _printingId == null && !_loadingSettings
                    ? () => _print(
                        Printer(
                            address: _savedSettings!.address,
                            name: _savedSettings!.name,
                            connectionType: _savedSettings!.transport ==
                                    ReceiptTransport.ble
                                ? ConnectionType.BLE
                                : null),
                        testReceipt: true)
                    : null,
              ),
            if (_savedSettings != null)
              TextButton(
                onPressed: _printingId == null
                    ? () async {
                        try {
                          await _settingsStore.clear(widget.cafeId);
                          if (mounted) setState(() => _savedSettings = null);
                        } catch (error) {
                          if (mounted) {
                            setState(() =>
                                _error = 'Could not forget printer: $error');
                          }
                        }
                      }
                    : null,
                child: const Text('Forget printer'),
              ),
            TextButton(
              onPressed: _printingId == null
                  ? () => Navigator.of(context).pop()
                  : null,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
