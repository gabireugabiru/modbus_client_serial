import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

class RawMessage {
  final int key;
  final dynamic error;
  final dynamic message;
  const RawMessage(this.key, this.message, this.error);
}

class CloseMessage {}

class Thread<Send, Receive> {
  SendPort? sendToThread;
  ReceivePort? receiveFromThread;
  final Random random = Random();
  final Map<int, Completer<Receive?>> completers = {};
  String? debugName;
  Isolate? isolate;

  Future<void> spawn({String? debugName}) async {
    debugName = debugName;
    if (sendToThread != null) {
      throw Exception("Thread already started");
    }
    // Create a receive port and add its initial message handler.
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      stdout.writeln("${debugName ?? "Thread"}: Initialized");
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ));
    };

    // Spawn the isolate.
    try {
      isolate = await Isolate.spawn(
        threadStart,
        (initPort.sendPort),
        debugName: debugName,
      );
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort receivePort, SendPort sendPort) =
        await connection.future;
    sendToThread = sendPort;
    receiveFromThread = receivePort;

    receiveFromThread?.listen(mainReceive);
  }

  Thread();

  void mainReceive(dynamic rawMessage) {
    if (rawMessage is RemoteError) {
      throw Exception("Bad State, remote ERROR");
    } else if (rawMessage is RawMessage) {
      if (rawMessage.error != null) {
        completers[rawMessage.key]?.completeError(rawMessage.error);
        completers.remove(rawMessage.key);
      }

      if (rawMessage.message is Receive?) {
        completers[rawMessage.key]?.complete(rawMessage.message);
        completers.remove(rawMessage.key);
      } else {
        throw Exception(
          "Invalid type received ${rawMessage.message.runtimeType}",
        );
      }
    } else {
      throw Exception(
        "Malformed message $rawMessage of type ${rawMessage.runtimeType} ",
      );
    }
  }

  void threadReceive(ReceivePort receivePort, SendPort sendPort) {
    receivePort.listen((rawMessage) async {
      if (rawMessage is CloseMessage) {
        receivePort.close();
        return;
      }

      if (rawMessage is! RawMessage) {
        throw Exception(
          "Malformed message $rawMessage of type ${rawMessage.runtimeType} ",
        );
      }
      try {
        final res = await handleThreadReceive(rawMessage.message);
        sendPort.send(RawMessage(rawMessage.key, res, null));
      } catch (err) {
        sendPort.send(RawMessage(rawMessage.key, null, err));
      }
    });
  }

  Future<Receive?> handleThreadReceive(Send message) async {
    return null;
  }

  void threadStart(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    threadReceive(receivePort, sendPort);
  }

  bool isSpawned() => sendToThread != null;

  Future<Receive?> sendReceive(Send send) async {
    if (sendToThread == null) {
      throw Exception("Thread not initialized");
    }

    final key = random.nextInt(1 << 31);

    completers.putIfAbsent(key, () => Completer());
    sendToThread?.send(RawMessage(key, send, null));
    return completers[key]!.future;
  }

  Future<T?> request<T>(Send send) async {
    final res = await sendReceive(send);

    if (res is T?) {
      return res;
    } else {
      throw Exception("Incorrect return type ${res.runtimeType} for $send");
    }
  }

  /// **Warning** Closes the thread immediately, any process not finished will be lost
  void closeThread() {
    if (sendToThread != null) {
      sendToThread?.send(CloseMessage());
      receiveFromThread?.close();
      isolate?.kill();
      stdout.writeln("${debugName ?? "Thread"}: Closed");
      receiveFromThread?.close();
    }
  }
}
