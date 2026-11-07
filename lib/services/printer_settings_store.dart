import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'thermal_printer_service.dart';

enum ReceiptTransport { ble, classic }

enum ReceiptEncoding { ascii, cp1252 }

class ReceiptPrinterSettings {
  const ReceiptPrinterSettings({
    required this.address,
    required this.name,
    this.paperWidth = ReceiptPaperWidth.mm58,
    this.autoPrint = true,
    this.transport = ReceiptTransport.ble,
    this.encoding = ReceiptEncoding.ascii,
    this.feedLines = 3,
    this.cut = true,
  });

  final String address;
  final String name;
  final ReceiptPaperWidth paperWidth;
  final bool autoPrint;
  final ReceiptTransport transport;
  final ReceiptEncoding encoding;
  final int feedLines;
  final bool cut;

  Map<String, dynamic> toJson() => {
        'address': address,
        'name': name,
        'paperWidth': paperWidth.millimeters,
        'autoPrint': autoPrint,
        'transport': transport.name,
        'encoding': encoding.name,
        'feedLines': feedLines,
        'cut': cut,
      };

  factory ReceiptPrinterSettings.fromJson(Map<String, dynamic> data) {
    final transport = data['transport'] ?? 'ble';
    final encoding = data['encoding'] ?? 'ascii';
    final feed = data['feedLines'] ?? 3;
    final cut = data['cut'] ?? true;
    if (!ReceiptTransport.values.any((v) => v.name == transport) ||
        !ReceiptEncoding.values.any((v) => v.name == encoding) ||
        feed is! int ||
        feed < 0 ||
        feed > 10 ||
        cut is! bool) {
      throw const FormatException('Invalid printer profile.');
    }
    final address = data['address'];
    final name = data['name'];
    final width = data['paperWidth'];
    final autoPrint = data['autoPrint'];
    if (address is! String ||
        address.trim().isEmpty ||
        name is! String ||
        (width != 58 && width != 80) ||
        autoPrint is! bool) {
      throw const FormatException('Invalid saved printer settings.');
    }
    return ReceiptPrinterSettings(
      address: address,
      name: name,
      paperWidth: width == 80 ? ReceiptPaperWidth.mm80 : ReceiptPaperWidth.mm58,
      autoPrint: autoPrint,
      transport: ReceiptTransport.values.byName(transport as String),
      encoding: ReceiptEncoding.values.byName(encoding as String),
      feedLines: feed,
      cut: cut,
    );
  }
}

abstract interface class PrinterSettingsStore {
  Future<ReceiptPrinterSettings?> load(String? cafeId);
  Future<void> save(String? cafeId, ReceiptPrinterSettings settings);
  Future<void> clear(String? cafeId);

  /// Claims an automatic send before touching the device. An uncertain or failed
  /// send stays claimed: another attempt must be an explicit receipt reprint.
  Future<bool> claimAutoPrint(String? cafeId, String billId, String address);
}

class SharedPreferencesPrinterSettingsStore implements PrinterSettingsStore {
  SharedPreferencesPrinterSettingsStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;
  static final Set<String> _claiming = {};

  String _scope(String? cafeId) =>
      cafeId == null ? 'legacy' : 'cafe:${Uri.encodeComponent(cafeId)}';
  String _settingsKey(String? cafeId) =>
      'brewverse.printer.v1.${_scope(cafeId)}';

  @override
  Future<ReceiptPrinterSettings?> load(String? cafeId) async {
    final value = (await _preferences()).getString(_settingsKey(cafeId));
    if (value == null) return null;
    try {
      return ReceiptPrinterSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(value) as Map),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(String? cafeId, ReceiptPrinterSettings settings) async {
    ReceiptPrinterSettings.fromJson(settings.toJson());
    if (!await (await _preferences())
        .setString(_settingsKey(cafeId), jsonEncode(settings.toJson()))) {
      throw StateError('Could not save receipt printer settings.');
    }
  }

  @override
  Future<void> clear(String? cafeId) async {
    if (!await (await _preferences()).remove(_settingsKey(cafeId))) {
      throw StateError('Could not remove receipt printer settings.');
    }
  }

  @override
  Future<bool> claimAutoPrint(
    String? cafeId,
    String billId,
    String address,
  ) async {
    final key = 'brewverse.receiptAttempt.v1.${_scope(cafeId)}.'
        '${Uri.encodeComponent(billId)}.${Uri.encodeComponent(address)}';
    // Prevent parallel callbacks in this app process from both claiming a send.
    if (!_claiming.add(key)) return false;
    try {
      final preferences = await _preferences();
      if (preferences.getBool(key) == true) return false;
      if (!await preferences.setBool(key, true)) {
        throw StateError('Could not persist the receipt attempt.');
      }
      return true;
    } finally {
      _claiming.remove(key);
    }
  }
}
