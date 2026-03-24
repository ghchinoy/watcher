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

  bool _isDisposed = false;

  BeadsService(this.workingDirectory);

  Future<void> _ensureDaemonRunning() async {
    if (_isDisposed) throw Exception('Service disposed');
    if (_daemonProcess != null) return;
    if (_isInitializing) {
      // Simple backoff wait if currently initializing
      await Future.delayed(const Duration(milliseconds: 100));
      return _ensureDaemonRunning();
    }
    
    _isInitializing = true;
    try {
      // Find the bundled daemon binary.
      String daemonPath = 'daemon/watcher-daemon';
      
      if (File(daemonPath).existsSync()) {
        // We are in dev mode, running from the project root. Make it absolute
        // so it works when Process.start changes the working directory.
        daemonPath = File(daemonPath).absolute.path;
      } else {
        // If we are running from a built app bundle on macOS, the executable is in Contents/MacOS
        final execPath = Platform.resolvedExecutable;
        final bundleDir = File(execPath).parent.parent;
        final bundledDaemon = File('${bundleDir.path}/Resources/watcher-daemon');
        if (bundledDaemon.existsSync()) {
          daemonPath = bundledDaemon.path;
        }
      }

      _daemonProcess = await Process.start(
        daemonPath,
        [workingDirectory],
        workingDirectory: workingDirectory,
      );

      // Prevent unhandled async exceptions if the process crashes and the pipe breaks
      _daemonProcess!.stdin.done.catchError((_) {});

      // Use LineSplitter to frame the JSON-RPC messages (one per line)
      _daemonProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final response = jsonDecode(line);
          
          // Handle server-initiated notifications
          if (response['method'] == 'boot_status') {
             debugPrint('Daemon Notification: ${response['params']}');
             return;
          }
          
          final id = response['id'] as int?;
          if (id != null && _pendingRequests.containsKey(id)) {
            if (response['error'] != null) {
              _pendingRequests[id]!.completeError(
                  Exception(response['error']['message']));
            } else {
              _pendingRequests[id]!.complete(response['result']);
            }
            _pendingRequests.remove(id);
          }
        } catch (e) {
          debugPrint('Failed to process daemon output object: $e');
        }
      });

      _daemonProcess!.stderr.transform(utf8.decoder).listen((line) {
        debugPrint('Daemon STDERR: $line');
      });

      _daemonProcess!.exitCode.then((code) {
        debugPrint('Daemon exited with code $code');
        _daemonProcess = null;
        if (!_isDisposed) {
          for (var completer in _pendingRequests.values) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('Daemon crashed (exit code $code)'));
            }
          }
        }
        _pendingRequests.clear();
      });
      
    } finally {
      _isInitializing = false;
    }
  }

  Future<dynamic> _sendRpcRequest(String method, [dynamic params]) async {
    await _ensureDaemonRunning();
    
    if (_daemonProcess == null) {
      throw Exception('Daemon process failed to start or died');
    }

    final id = _requestId++;
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    final request = {
      'jsonrpc': '2.0',
      'method': method,
      ...?params != null ? {'params': params} : null,
      'id': id,
    };

    try {
      _daemonProcess!.stdin.writeln(jsonEncode(request));
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }
    
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw Exception('Daemon timed out after 15s waiting for Dolt server to boot. Try selecting the project again.');
      },
    );
  }

  Future<List<Interaction>> getInteractions() async {
    final file = File('$workingDirectory/.beads/backup/events.jsonl');
    if (!await file.exists()) {
      return [];
    }

    final List<Interaction> interactions = [];
    final lines = await file.readAsLines();
    // Read from end to get most recent first, take up to 50
    for (var line in lines.reversed.take(50)) {
      if (line.trim().isEmpty) continue;
      try {
        final Map<String, dynamic> data = jsonDecode(line);
        interactions.add(Interaction.fromJson(data));
      } catch (e) {
        debugPrint('Error parsing interaction JSON: $e');
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

  Future<void> updateIssue(String id, {String? status, int? priority, String? owner, String? assignee, required String actor}) async {
    final Map<String, dynamic> updates = {};
    if (status != null) updates['status'] = status;
    if (priority != null) updates['priority'] = priority;
    if (owner != null) updates['owner'] = owner;
    if (assignee != null) updates['assignee'] = assignee;

    if (updates.isEmpty) return;

    await _sendRpcRequest('update_issue', {
      'id': id,
      'updates': updates,
      'actor': actor,
    });
  }
  
  Future<String?> getVersion() async {
    final result = await _sendRpcRequest('get_version', {});
    if (result is String) {
      return result;
    }
    return null;
  }

  Future<String?> getCliVersion() async {
    try {
      final result = await Process.run('bd', ['version'], workingDirectory: workingDirectory);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      debugPrint('Failed to get CLI version: $e');
    }
    return null;
  }

  Future<String?> getProjectRequiredVersion() async {
    try {
      final file = File('$workingDirectory/.beads/metadata.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        return data['required_version'] as String?;
      }
    } catch (e) {
      debugPrint('Failed to read project required version: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getComments(String issueId) async {
    final result = await _sendRpcRequest('get_comments', {'id': issueId});
    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<void> addComment(String issueId, String comment, {required String actor}) async {
    await _sendRpcRequest('add_comment', {
      'id': issueId,
      'comment': comment,
      'actor': actor,
    });
  }

  Future<List<Map<String, String>>> getPeers() async {
    final result = await _sendRpcRequest('get_peers');
    if (result == null) return [];
    
    final List<Map<String, String>> peers = [];
    final list = result as List<dynamic>;
    for (var item in list) {
      final map = item as Map<String, dynamic>;
      peers.add({
        'name': map['name'] as String? ?? '',
        'url': map['url'] as String? ?? '',
      });
    }
    return peers;
  }

  Future<void> addPeer(String name, String url) async {
    await _sendRpcRequest('add_peer', {
      'name': name,
      'url': url,
    });
  }

  Future<void> syncPeer([String? peer]) async {
    await _sendRpcRequest('sync_peer', {
      ...?peer != null ? {'peer': peer} : null,
    });
  }

  void dispose() {
    _isDisposed = true;
    _daemonProcess?.kill();
    _daemonProcess = null;
    for (var completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Service disposed'));
      }
    }
    _pendingRequests.clear();
  }
}
