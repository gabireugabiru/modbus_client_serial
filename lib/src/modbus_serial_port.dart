import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_serial/modbus_client_serial.dart';

import 'package:libserialport/libserialport.dart';
import 'package:synchronized/synchronized.dart';

/// serial port client implementation
class LibSerialPort extends ModbusSerialPort {
  final ModbusIntEnum baudRate;
  final SerialDataBits dataBits;
  final SerialStopBits stopBits;
  final SerialParity parity;
  final SerialFlowControl flowControl;
  SerialPort? _serialPort;
  final _lock = Lock();
  bool reading = false;

  LibSerialPort(this.portName, this.baudRate, this.dataBits, this.stopBits,
      this.parity, this.flowControl);

  /// The serial port name
  final String portName;

  @override
  String get name => portName;

  @override
  bool get isOpen => _serialPort != null;

  /// Opens the serial port for reading and writing.
  @override
  Future<bool> open() async {
    if (_serialPort != null) {
      await _lock.synchronized(() {
        _serialPort!.close();
        _serialPort!.dispose();
      }, timeout: Duration(milliseconds: 500));
      _serialPort = null;
    }

    // New connection
    _serialPort = SerialPort(portName);
    if (!_serialPort!.openReadWrite()) {
      await _lock.synchronized(() => _serialPort!.dispose(),
          timeout: Duration(milliseconds: 500));
      _serialPort = null;
      return false;
    }

    // Update the config for your setup
    SerialPortConfig serialConfig = SerialPortConfig()
      ..baudRate = baudRate.intValue
      ..bits = dataBits.intValue
      ..stopBits = stopBits.intValue
      ..parity = parity.intValue
      ..setFlowControl(flowControl.intValue);
    _serialPort!.config = serialConfig;

    return true;
  }

  @override
  Future<void> close() async {
    if (_serialPort != null) {
      await _lock.synchronized(() {
        while (reading) {}
        _serialPort!.close();
        _serialPort!.dispose();
        _serialPort = null;
      }, timeout: Duration(milliseconds: 500));
    }
  }

  @override
  Future<void> flush() async {
    if (_serialPort != null) {
      return await _lock.synchronized(() => _serialPort!.flush(),
          timeout: Duration(milliseconds: 500));
    }
  }

  @override
  Future<Uint8List> read(int bytes, {Duration? timeout}) async {
    if (_serialPort != null) {
      var res = await Isolate.run(() {
        Timer(timeout ?? Duration(days: 2), () => Isolate.exit());
        try {
          reading = true;
          final a = _serialPort!.read(bytes,
              timeout: timeout == null ? -1 : timeout.inMilliseconds);
          reading = false;
          return a;
        } catch (err) {
          return null;
        }
      });

      if (res == null) {
        throw Exception("Thread Panicked");
      }
      return res;
    }
    reading = false;
    return Uint8List(0);
  }

  @override
  Future<int> write(Uint8List bytes, {Duration? timeout}) async {
    if (_serialPort != null) {
      return await _lock.synchronized(
          () => _serialPort!.write(bytes,
              timeout: timeout == null ? -1 : timeout.inMilliseconds),
          timeout: timeout);
    }
    return 0;
  }
}
