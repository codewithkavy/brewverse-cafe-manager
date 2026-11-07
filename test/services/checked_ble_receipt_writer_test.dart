import 'package:brewverse_cafe_manager/services/checked_ble_receipt_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

void main() {
  final printer = Printer(address: 'AA:BB', connectionType: ConnectionType.BLE);
  BleService service(List<CharacteristicProperty> properties) =>
      BleService('1800', [BleCharacteristic('2A00', properties, [])]);

  test('sends bounded BLE chunks and prefers acknowledged writes', () async {
    final chunks = <List<int>>[];
    final responses = <bool>[];
    final writer = CheckedBleReceiptWriter(
      discoverServices: (_) async => [
        service([CharacteristicProperty.writeWithoutResponse]),
        service([CharacteristicProperty.write]),
      ],
      writeChunk: (_, bytes, withResponse) async {
        chunks.add(bytes);
        responses.add(withResponse);
      },
      delay: (_) async {},
    );
    final bytes = List.generate(49, (index) => index);
    await writer.write(printer, bytes);
    expect(chunks.map((chunk) => chunk.length), [20, 20, 9]);
    expect(chunks.expand((chunk) => chunk), bytes);
    expect(responses, everyElement(isTrue));
  });

  test('supports printers exposing only write without response', () async {
    var acknowledged = true;
    final writer = CheckedBleReceiptWriter(
      discoverServices: (_) async => [
        service([CharacteristicProperty.writeWithoutResponse]),
      ],
      writeChunk: (_, bytes, withResponse) async {
        acknowledged = withResponse;
      },
      delay: (_) async {},
    );
    await writer.write(printer, [1, 2, 3]);
    expect(acknowledged, isFalse);
  });

  test('does not claim success when no writable characteristic exists',
      () async {
    final writer = CheckedBleReceiptWriter(
      discoverServices: (_) async => [
        service([CharacteristicProperty.read])
      ],
      writeChunk: (_, bytes, withResponse) async => fail('Must not write'),
    );
    await expectLater(writer.write(printer, [1]), throwsStateError);
  });

  test('propagates partial BLE write failure without retrying a chunk',
      () async {
    var writes = 0;
    final writer = CheckedBleReceiptWriter(
      discoverServices: (_) async => [
        service([CharacteristicProperty.write])
      ],
      writeChunk: (_, bytes, withResponse) async {
        writes++;
        if (writes == 2) throw StateError('Printer disconnected');
      },
      delay: (_) async {},
    );
    await expectLater(
      writer.write(printer, List.filled(60, 1)),
      throwsStateError,
    );
    expect(writes, 2);
  });
}
