import 'dart:convert';
import 'dart:io';

void main() async {
  final process = await Process.start(
    '/Users/ghchinoy/projects/watcher/daemon/watcher-daemon',
    ['/Users/ghchinoy/projects/riptide'],
    workingDirectory: '/Users/ghchinoy/projects/watcher',
  );

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    print("STDOUT: \${line.substring(0, line.length > 50 ? 50 : line.length)}...");
  });

  process.stderr.transform(utf8.decoder).listen((line) {
    print("STDERR: \$line");
  });

  process.exitCode.then((code) {
    print("EXIT: \$code");
  });

  process.stdin.writeln('{"method": "graph", "id": 1}');
}
