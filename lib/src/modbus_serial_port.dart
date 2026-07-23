import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_serial/modbus_client_serial.dart';

import 'package:modbus_client_serial/thread/serial.dart';

/// serial port client implementation
class LibSerialPort extends ModbusSerialPort {
  final ModbusIntEnum baudRate;
  final SerialDataBits dataBits;
  final SerialStopBits stopBits;
  final SerialParity parity;
  final SerialFlowControl flowControl;
  SerialWorker? serial;
  LibSerialPort(this.portName, this.baudRate, this.dataBits, this.stopBits,
      this.parity, this.flowControl);

  /// The serial port name
  final String portName;
  bool _open = false;

  Future<void> enforceSpawned() async {
    if (serial == null) {
      serial = SerialWorker();
      await serial!.spawn(debugName: "Serial Isolate");
    }
  }

  @override
  String get name => portName;

  @override
  bool get isOpen => _open;

  /// Opens the serial port for reading and writing.
  @override
  Future<bool> open() async {
    await enforceSpawned();

    if (await serial!.isOpen()) {
      await serial!.close();
      await serial!.dispose();
      _open = false;
    }

    // New connection
    await serial!.setPort(portName);

    if (!await serial!.openReadWrite()) {
      await serial!.dispose();
      _open = false;
      return false;
    }

    // Update the config for your setup
    await serial!.setConfig(
        baudRate: baudRate.intValue,
        bits: dataBits.intValue,
        stopbits: stopBits.intValue,
        flowctrl: flowControl.intValue,
        parity: parity.intValue);

    _open = await serial!.isOpen();
    return true;
  }

  @override
  Future<void> close() async {
    await enforceSpawned();

    if (await serial!.isOpen()) {
      await serial!.close();
      await serial!.dispose();
    }
    _open = await serial!.isOpen();

    serial!.closeThread();
    serial = null;
  }

  @override
  Future<void> flush() async {
    await enforceSpawned();

    await serial!.flush();
  }

  @override
  Future<Uint8List> read(int bytes, {Duration? timeout}) async {
    await enforceSpawned();

    return await serial!.read(bytes, timeout: timeout?.inMilliseconds ?? -1) ??
        Uint8List(0);
  }

  @override
  Future<int> write(Uint8List bytes, {Duration? timeout}) async {
    await enforceSpawned();

    return await serial!.write(bytes, timeout: timeout?.inMilliseconds ?? -1);
  }
}
