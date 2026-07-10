import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_watcher/services/beads_service.dart';

class MockIOSink implements IOSink {
  final List<String> writtenLines = [];

  @override
  void write(Object? obj) {
    if (obj != null) {
      writtenLines.add(obj.toString());
    }
  }

  @override
  void writeln([Object? obj = '']) {
    writtenLines.add('$obj\n');
  }

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future.value();

  @override
  Future<void> flush() => Future.value();

  @override
  void writeAll(Iterable objects, [String separator = ""]) {}

  @override
  void writeCharCode(int charCode) {}
}

class MockProcess implements Process {
  final StreamController<List<int>> stdoutController = StreamController<List<int>>();
  final StreamController<List<int>> stderrController = StreamController<List<int>>();
  final MockIOSink mockStdin = MockIOSink();
  final Completer<int> exitCodeCompleter = Completer<int>();

  MockProcess() {
    // BeadsService listens for boot_status notifications.
    // Let's send the connecting and ready states so BeadsService finishes initialization.
    Future.microtask(() {
      sendLine('{"jsonrpc":"2.0","method":"boot_status","params":{"status":"connecting_to_database","mode":"embedded"}}');
      sendLine('{"jsonrpc":"2.0","method":"boot_status","params":{"status":"ready","mode":"embedded"}}');
    });
  }

  void sendLine(String line) {
    if (!stdoutController.isClosed) {
      stdoutController.add(utf8.encode('$line\n'));
    }
  }

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  IOSink get stdin => mockStdin;

  @override
  Future<int> get exitCode => exitCodeCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    stdoutController.close();
    stderrController.close();
    if (!exitCodeCompleter.isCompleted) {
      exitCodeCompleter.complete(0);
    }
    return true;
  }

  @override
  int get pid => 98765;
}

void main() {
  group('BeadsService daemon initialization race (RACE-01)', () {
    test('concurrent calls share a single daemon initialization', () async {
      int spawnCount = 0;
      final mockProcesses = <MockProcess>[];

      // A mock process start function that increments counter and returns a mock process
      Future<Process> mockProcessStart(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true,
        bool runInShell = false,
        ProcessStartMode mode = ProcessStartMode.normal,
      }) async {
        spawnCount++;
        final proc = MockProcess();
        mockProcesses.add(proc);
        return proc;
      }

      final service = BeadsService(
        '/dummy/path',
        processStart: mockProcessStart,
      );

      // Now, let's trigger multiple RPC requests concurrently.
      // Under the hood, each call will run _ensureDaemonRunning().
      // They should all await the same single completer future, and spawnCount should be exactly 1.
      final futures = Future.wait([
        service.getVersion(),
        service.getVersion(),
        service.getVersion(),
      ]);

      // Provide replies to the getVersion calls (id 1, 2, 3)
      await Future.delayed(const Duration(milliseconds: 50));
      for (final proc in mockProcesses) {
        proc.sendLine('{"jsonrpc":"2.0","result":"1.2.3","id":1}');
        proc.sendLine('{"jsonrpc":"2.0","result":"1.2.3","id":2}');
        proc.sendLine('{"jsonrpc":"2.0","result":"1.2.3","id":3}');
      }

      final results = await futures;

      expect(spawnCount, 1);
      expect(results, ['1.2.3', '1.2.3', '1.2.3']);

      // Cleanup
      service.dispose();
      for (final proc in mockProcesses) {
        proc.kill();
      }
    });

    test('recovers and retries initialization if it fails', () async {
      int spawnCount = 0;
      final mockProcesses = <MockProcess>[];

      Future<Process> mockProcessStart(
        String executable,
        List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true,
        bool runInShell = false,
        ProcessStartMode mode = ProcessStartMode.normal,
      }) async {
        spawnCount++;
        if (spawnCount == 1) {
          // First attempt fails immediately
          throw Exception('Failed to spawn daemon process');
        }
        final proc = MockProcess();
        mockProcesses.add(proc);
        return proc;
      }

      final service = BeadsService(
        '/dummy/path',
        processStart: mockProcessStart,
      );

      // First call should fail because process start throws
      await expectLater(service.getVersion(), throwsException);

      // Second call should retry starting the daemon and succeed
      final future = service.getVersion();

      // Wait for stdin to receive the command from the second process
      await Future.doWhile(() async {
        if (mockProcesses.isNotEmpty && mockProcesses[0].mockStdin.writtenLines.isNotEmpty) {
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 10));
        return true;
      });

      expect(mockProcesses.length, 1);
      final written = mockProcesses[0].mockStdin.writtenLines.first;
      final requestObj = jsonDecode(written);
      final reqId = requestObj['id'];

      mockProcesses[0].sendLine('{"jsonrpc":"2.0","result":"1.2.3","id":$reqId}');

      final version = await future;
      expect(version, '1.2.3');
      expect(spawnCount, 2);

      // Cleanup
      service.dispose();
      for (final proc in mockProcesses) {
        proc.kill();
      }
    });
  });
}
