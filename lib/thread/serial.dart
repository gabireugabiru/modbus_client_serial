import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';
import 'package:modbus_client_serial/thread/thread.dart';
import 'package:synchronized/synchronized.dart';

class SerialSend {
  const SerialSend();
}

class SerialReceive {
  const SerialReceive();
}

class SerialReadSend extends SerialSend {
  final int bytes;
  final int timeout;
  SerialReadSend(this.bytes, this.timeout);
}

class SerialReadReceive extends SerialReceive {
  final Uint8List? receive;
  const SerialReadReceive(this.receive);
}

class SerialCloseSend extends SerialSend {}

class SerialCloseReceive extends SerialReceive {
  final bool ok;
  const SerialCloseReceive(this.ok);
}

class SerialDisposeSend extends SerialSend {}

class SerialDisposeReceive extends SerialReceive {}

class SerialPortNameSend extends SerialSend {
  final String portname;
  const SerialPortNameSend(this.portname);
}

class SerialPortNameReceive extends SerialReceive {}

class SerialConfigSend extends SerialSend {
  final int baudRate;
  final int parity;
  final int bits;
  final int stopbits;
  final int flowctrl;

  const SerialConfigSend(
      {required this.baudRate,
      required this.bits,
      required this.stopbits,
      required this.flowctrl,
      required this.parity});
}

class SerialConfigReceive extends SerialReceive {}

class SerialOpenReadWriteSend extends SerialSend {}

class SerialOpenReadWriteReceive extends SerialReceive {
  final bool ok;
  const SerialOpenReadWriteReceive(this.ok);
}

class SerialFlushSend extends SerialSend {}

class SerialFlushReceive extends SerialReceive {}

class SerialWriteSend extends SerialSend {
  final Uint8List bytes;
  final int timeout;

  const SerialWriteSend(this.bytes, this.timeout);
}

class SerialWriteReceive extends SerialReceive {
  final int res;
  const SerialWriteReceive(this.res);
}

class SerialIsOpenSend extends SerialSend {}

class SerialIsOpenReceive extends SerialReceive {
  final bool ok;
  const SerialIsOpenReceive(this.ok);
}

class SerialWorker extends Thread<SerialSend, SerialReceive> {
  SerialPort? serial;
  final Lock lock = Lock();

  Future<bool> isOpen() async {
    return (await request<SerialIsOpenReceive>(SerialIsOpenSend()))?.ok ??
        false;
  }

  Future<int> write(Uint8List bytes, {int timeout = -1}) async {
    return (await request<SerialWriteReceive>(SerialWriteSend(bytes, timeout)))
            ?.res ??
        0;
  }

  Future<void> flush() async {
    await request<SerialFlushReceive>(SerialFlushSend());
  }

  Future<bool> openReadWrite() async {
    return (await request<SerialOpenReadWriteReceive>(
                SerialOpenReadWriteSend()))
            ?.ok ??
        false;
  }

  Future<void> setConfig(
      {required int baudRate,
      required int bits,
      required int stopbits,
      required int flowctrl,
      required int parity}) async {
    await request<SerialConfigReceive>(SerialConfigSend(
        baudRate: baudRate,
        bits: bits,
        stopbits: stopbits,
        flowctrl: flowctrl,
        parity: parity));
  }

  Future<void> setPort(String name) async {
    await request<SerialPortNameReceive>(SerialPortNameSend(name));
  }

  Future<void> dispose() async {
    await request<SerialDisposeReceive>(SerialDisposeSend());
  }

  Future<bool> close() async {
    return (await request<SerialCloseReceive>(SerialCloseSend()))?.ok ?? false;
  }

  Future<Uint8List?> read(int bytes, {int timeout = -1}) async {
    return (await request<SerialReadReceive>(SerialReadSend(bytes, timeout)))
        ?.receive;
  }

  @override
  Future<SerialReceive?> handleThreadReceive(SerialSend message) async {
    switch (message) {
      case SerialIsOpenSend():
        return SerialIsOpenReceive(serial != null);
      case SerialWriteSend(:var bytes, :var timeout):
        return await lock.synchronized(() {
          try {
            return SerialWriteReceive(
                serial?.write(bytes, timeout: timeout) ?? 0);
          } catch (e) {
            return SerialWriteReceive(0);
          }
        },
            timeout: Duration(
                milliseconds: timeout <= 0 ? 99999999 : timeout + 500));
      case SerialFlushSend():
        return await lock.synchronized(() {
          serial?.flush();
          return SerialFlushReceive();
        }, timeout: Duration(milliseconds: 500));
      case SerialOpenReadWriteSend():
        return await lock.synchronized(() {
          return SerialOpenReadWriteReceive(serial?.openReadWrite() ?? false);
        }, timeout: Duration(milliseconds: 500));
      case SerialConfigSend(
          :var baudRate,
          :var bits,
          :var stopbits,
          :var flowctrl,
          :var parity
        ):
        return await lock.synchronized(() {
          SerialPortConfig serialConfig = SerialPortConfig()
            ..baudRate = baudRate
            ..bits = bits
            ..stopBits = stopbits
            ..parity = parity
            ..setFlowControl(flowctrl);
          serial?.config = serialConfig;
          return SerialConfigReceive();
        }, timeout: Duration(milliseconds: 500));
      case SerialPortNameSend(:var portname):
        return await lock.synchronized(() {
          serial = SerialPort(portname);
          return SerialPortNameReceive();
        }, timeout: Duration(milliseconds: 500));
      case SerialDisposeSend():
        return await lock.synchronized(() {
          serial?.dispose();
          serial = null;
          return SerialDisposeReceive();
        }, timeout: Duration(milliseconds: 500));
      case SerialCloseSend():
        return await lock.synchronized(() {
          final ok = serial?.close();
          if (ok == true) {
            serial = null;
          }
          return SerialCloseReceive(ok ?? false);
        }, timeout: Duration(milliseconds: 500));
      case SerialReadSend(:var bytes, :var timeout):
        return await lock.synchronized(() {
          if (serial == null) {
            return SerialReadReceive(null);
          }
          try {
            return SerialReadReceive(serial!.read(bytes, timeout: timeout));
          } catch (e) {
            return SerialReadReceive(null);
          }
        },
            timeout: Duration(
                milliseconds: timeout <= 0 ? 99999999 : timeout + 500));

      default:
        throw Exception("${message.runtimeType} is not implemented ");
    }
  }
}
