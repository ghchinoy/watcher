import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/issue.dart';
import '../models/interaction.dart';
import 'package:flutter/foundation.dart';

class BeadsService {
  final String workingDirectory;
  Process? _daemonProcess;
  int _requestId = 1;
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  bool _isInitializing = false;

  BeadsService(this.workingDirectory);

  Future<void> _ensureDaemonRunning() async {
    if (_daemonProcess != null) return;
    if (_isInitializing) {
      // Simple backoff wait if currently initializing
      await Future.delayed(const Duration(milliseconds: 100));
      return _ensureDaemonRunning();
    }
    
    _isInitializing = true;
    try {
      // Find the bundled daemon binary. During dev it's in daemon/watcher-daemon.
      // In production, we'll need to locate it relative to the App bundle.
      // For now, we assume it's built in the project root/daemon directory.
      String daemonPath = 'daemon/watcher-daemon';
      
      // If we are running from a built app bundle on macOS, the executable is in Contents/MacOS
      // We can look for it in the same directory as our executable or Resources.
      if (!File(daemonPath).existsSync()) {
        final execPath = Platform.resolvedExecutable;
        final bundleDir = File(execPath).parent.parent;
        final bundledDaemon = File('${bundleDir.path}/Resources/watcher-daemon');
        if (bundledDaemon.existsSync()) {
          daemonPath = bundledDaemon.path;
        } else {
           // Fallback to expecting it in PATH or just fail later
        }
      }

      _daemonProcess = await Process.start(
        daemonPath,
        [workingDirectory],
        workingDirectory: workingDirectory,
      );

      _daemonProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final response = jsonDecode(line);
          final id = response['id'] as int?;
          if (id != null && _pendingRequests.containsKey(id)) {
            if (response['error'] != null) {
              _pendingRequests[id]!.completeError(Exception(response['error']['message']));
            } else {
              _pendingRequests[id]!.complete(response['result']);
            }
            _pendingRequests.remove(id);
          }
        } catch (e) {
          debugPrint('Failed to parse daemon output: $line');
        }
      });

      _daemonProcess!.stderr.transform(utf8.decoder).listen((line) {
        debugPrint('Daemon STDERR: $line');
      });

      _daemonProcess!.exitCode.then((code) {
        debugPrint('Daemon exited with code $code');
        _daemonProcess = null;
        for (var completer in _pendingRequests.values) {
          completer.completeError(Exception('Daemon crashed'));
        }
        _pendingRequests.clear();
      });
      
    } finally {
      _isInitializing = false;
    }
  }

  Future<dynamic> _sendRpcRequest(String method, [dynamic params]) async {
    await _ensureDaemonRunning();
    
    final id = _requestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    final request = {
      'jsonrpc': '2.0',
      'method': method,
      ...?params != null ? {'params': params} : null,
      'id': id,
    };

    _daemonProcess!.stdin.writeln(jsonEncode(request));
    
    return completer.future;
  }

  Future<List<Interaction>> getInteractions() async {
    final file = File('$workingDirectory/.beads/interactions.jsonl');
    if (!await file.exists()) {
      return [];
    }

    final List<Interaction> interactions = [];
    final lines = await file.readAsLines();
    // Read from end to get most recent first, take up to 50
    for (var line in lines.reversed.take(50)) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line);
        interactions.add(Interaction.fromJson(json));
      } catch (e) {
        // ignore invalid lines
      }
    }
    return interactions;
  }

  Future<List<Issue>> getIssues() async {
    final result = await _sendRpcRequest('graph');
    
    if (result == null) return [];
    
    final List<Issue> issues = [];
    final list = result as List<dynamic>;
    for (var item in list) {
       issues.add(Issue.fromJson(item as Map<String, dynamic>));
    }
    return issues;
  }

  // Kept for backward compatibility but currently delegates to getIssues
  Future<List<GraphNode>> getGraph() async {
    final issues = await getIssues();
    // Wrap them in GraphNodes if that's what the UI expects, 
    // or just return dummy wrappers. Currently TreeView doesn't even use getGraph, 
    // it uses getIssues via AppState.
    return issues.map((i) => GraphNode(root: i)).toList();
  }

  Future<void> updateIssue(String id, {String? status, int? priority}) async {
    final Map<String, dynamic> updates = {};
    if (status != null) updates['status'] = status;
    if (priority != null) updates['priority'] = priority;

    if (updates.isEmpty) return;

    await _sendRpcRequest('update_issue', {
      'id': id,
      'updates': updates,
      'actor': 'Watcher UI',
    });
  }
  
  void dispose() {
    _daemonProcess?.kill();
    _daemonProcess = null;
  }
}
