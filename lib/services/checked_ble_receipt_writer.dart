import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

/// The plugin's printData logs and swallows BLE write failures. Use the same
/// exported BLE transport with checked writes so the app can report uncertainty.
class CheckedBleReceiptWriter {
  CheckedBleReceiptWriter({
    this.beforeChunk,
    Future<List<BleService>> Function(Printer)? discoverServices,
    Future<void> Function(BleCharacteristic, List<int>, bool)? writeChunk,
    Future<void> Function(Duration)? delay,
  })  : _discoverServices =
            discoverServices ?? ((printer) => printer.discoverServices()),
        _writeChunk = writeChunk ??
            ((characteristic, bytes, withResponse) =>
                characteristic.write(bytes, withResponse: withResponse)),
        _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final void Function()? beforeChunk;
  final Future<List<BleService>> Function(Printer) _discoverServices;
  final Future<void> Function(BleCharacteristic, List<int>, bool) _writeChunk;
  final Future<void> Function(Duration) _delay;

  Future<void> write(Printer printer, List<int> bytes) async {
    if (printer.connectionType != ConnectionType.BLE) {
      throw ArgumentError('Only BLE receipt printers are supported.');
    }
    if (bytes.isEmpty) throw ArgumentError('Receipt bytes cannot be empty.');
    final services = await _discoverServices(printer);
    final characteristics = services
        .expand((service) => service.characteristics)
        .toList(growable: false);
    BleCharacteristic? destination;
    var withResponse = true;
    for (final characteristic in characteristics) {
      if (characteristic.properties.contains(CharacteristicProperty.write)) {
        destination = characteristic;
        break;
      }
    }
    if (destination == null) {
      withResponse = false;
      for (final characteristic in characteristics) {
        if (characteristic.properties
            .contains(CharacteristicProperty.writeWithoutResponse)) {
          destination = characteristic;
          break;
        }
      }
    }
    if (destination == null) {
      throw StateError('The printer has no writable BLE characteristic.');
    }
    // 20 payload bytes fit the default ATT MTU (23) without negotiation and work
    // with small printer buffers. Partial-write errors intentionally propagate.
    for (var offset = 0; offset < bytes.length; offset += 20) {
      final end = (offset + 20).clamp(0, bytes.length);
      beforeChunk?.call();
      await _writeChunk(destination, bytes.sublist(offset, end), withResponse);
      await _delay(const Duration(milliseconds: 10));
    }
  }
}
