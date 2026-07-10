import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/issue.dart';
import '../models/interaction.dart';
import '../utils/app_logger.dart';

const macosDefaultPath =
    '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin';
const macosPathEnv = {'PATH': macosDefaultPath};

class BeadsService {
  static final _log = AppLogger('BeadsService');
  final String workingDirectory;

  /// Resolves the bd executable path. Pass a closure that reads
  /// the user's custom path from settings, defaulting to 'bd'.
  /// Defaults to a no-op resolver that always returns 'bd'.
  final String Function() _bdPathResolver;

  String get _bdExecutable => _bdPathResolver();

  Process? _daemonProcess;
  int _requestId = 1;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  /// REL-02: number of RPC requests that have timed out back-to-back with no
  /// intervening successful response. When it reaches
  /// [_maxConsecutiveTimeouts] the daemon is assumed hung/deadlocked and is
  /// force-restarted so subsequent requests don't time out indefinitely.
  /// Reset to 0 on any successful response.
  int _consecutiveTimeouts = 0;
  static const int _maxConsecutiveTimeouts = 2;

  /// Guards daemon startup so concurrent callers share a single initialization
  /// future instead of racing to spawn multiple daemons (RACE-01). Non-null
  /// while an initialization is in flight; cleared when it settles.
  Completer<void>? _initCompleter;

  bool _isDisposed = false;
  Function(String)? onModeChanged;

  final Future<Process> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    bool runInShell,
    ProcessStartMode mode,
  }) _processStart;

  final Duration _requestTimeout;

  BeadsService(
    this.workingDirectory, {
    this.onModeChanged,
    String Function()? bdPathResolver,
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
      bool runInShell,
      ProcessStartMode mode,
    })? processStart,
    Duration? requestTimeout,
  })  : _bdPathResolver = bdPathResolver ?? (() => 'bd'),
        _processStart = processStart ?? Process.start,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 15);

  Future<void> _ensureDaemonRunning() async {
    if (_isDisposed) throw Exception('Service disposed');
    if (_daemonProcess != null) return;

    // RACE-01: if another caller is already initializing, await the SAME future
    // rather than spinning on a timer (which could race and spawn a second
    // daemon, causing Dolt/noms LOCK contention).
    if (_initCompleter != null) {
      await _initCompleter!.future;
      // The initializer either set _daemonProcess or failed; if it failed,
      // surface that to this caller too.
      if (_daemonProcess == null) {
        throw Exception('Daemon initialization failed');
      }
      return;
    }

    final completer = Completer<void>();
    completer.future.ignore();
    _initCompleter = completer;
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
        final bundledDaemon = File(
          '${bundleDir.path}/Resources/watcher-daemon',
        );
        if (bundledDaemon.existsSync()) {
          daemonPath = bundledDaemon.path;
        }
      }

      _daemonProcess = await _processStart(
        daemonPath,
        [workingDirectory],
        workingDirectory: workingDirectory,
        environment: macosPathEnv,
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
                final params = response['params'] as Map<String, dynamic>;
                _log.info('Daemon boot_status', error: params);
                if (params.containsKey('mode') && onModeChanged != null) {
                  onModeChanged!(params['mode'] as String);
                }
                return;
              }

              final id = response['id'] as int?;
              if (id != null && _pendingRequests.containsKey(id)) {
                // REL-02: a matched response (even an error) proves the daemon
                // is alive and responsive, so the hang streak is broken.
                _consecutiveTimeouts = 0;
                if (response['error'] != null) {
                  _pendingRequests[id]!.completeError(
                    Exception(response['error']['message']),
                  );
                } else {
                  _pendingRequests[id]!.complete(response['result']);
                }
                _pendingRequests.remove(id);
              }
            } catch (e, st) {
              _log.warning(
                'Failed to process daemon output',
                error: e,
                stackTrace: st,
              );
            }
          });

      _daemonProcess!.stderr.transform(utf8.decoder).listen((line) {
        if (line.trim().isNotEmpty) _log.warning('Daemon stderr: $line');
      });

      _daemonProcess!.exitCode.then((code) {
        if (code != 0) {
          _log.error('Daemon exited unexpectedly', error: 'exit code $code');
        } else {
          _log.info('Daemon exited cleanly');
        }
        _daemonProcess = null;
        if (!_isDisposed) {
          for (var completer in _pendingRequests.values) {
            if (!completer.isCompleted) {
              completer.completeError(
                Exception('Daemon crashed (exit code $code)'),
              );
            }
          }
        }
        _pendingRequests.clear();
      });

      // Initialization succeeded (daemon spawned and listeners attached).
      if (!completer.isCompleted) completer.complete();
    } catch (e, st) {
      // Initialization failed: ensure no half-started state lingers and
      // propagate the error to every waiter.
      _log.error('Daemon initialization failed', error: e, stackTrace: st);
      _daemonProcess?.kill();
      _daemonProcess = null;
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    } finally {
      // Allow a subsequent call to retry initialization from scratch.
      _initCompleter = null;
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
      _requestTimeout,
      onTimeout: () {
        _pendingRequests.remove(id);

        // REL-02: track consecutive timeouts. A hung/deadlocked daemon would
        // otherwise make every subsequent request time out forever, because
        // _ensureDaemonRunning reuses the still-alive process. After
        // [_maxConsecutiveTimeouts] in a row, force-restart it so the next
        // request spawns a fresh daemon.
        _consecutiveTimeouts++;
        if (_consecutiveTimeouts >= _maxConsecutiveTimeouts) {
          _log.warning(
            'Daemon unresponsive after $_consecutiveTimeouts consecutive '
            'timeouts; force-restarting.',
          );
          _restartDaemon();
        }

        throw Exception(
          'Daemon timed out after ${_requestTimeout.inSeconds}s waiting for Dolt server to boot. Try selecting the project again.',
        );
      },
    );
  }

  /// REL-02: forcibly terminate the daemon so the next [_ensureDaemonRunning]
  /// spawns a fresh one. Killing the process triggers the existing
  /// `exitCode.then` handler, which nulls [_daemonProcess], fails any still
  /// pending requests, and clears [_pendingRequests]. We also reset the timeout
  /// counter so the fresh daemon starts with a clean slate.
  void _restartDaemon() {
    _consecutiveTimeouts = 0;
    final proc = _daemonProcess;
    // Null it eagerly so a concurrent caller doesn't reuse a dying process; the
    // exitCode handler is idempotent (it also nulls and clears).
    _daemonProcess = null;
    proc?.kill();
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
        final Map<String, dynamic> data = jsonDecode(line);
        interactions.add(Interaction.fromJson(data));
      } catch (e) {
        _log.warning('Error parsing interaction JSON', error: e);
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

  Future<void> updateIssue(
    String id, {
    String? status,
    int? priority,
    String? owner,
    String? assignee,
    String? parent,
    required String actor,
  }) async {
    final Map<String, dynamic> updates = {};
    if (status != null) updates['status'] = status;
    if (priority != null) updates['priority'] = priority;
    if (owner != null) updates['owner'] = owner;
    if (assignee != null) updates['assignee'] = assignee;
    if (parent != null) updates['parent'] = parent;

    if (updates.isEmpty) return;

    await _sendRpcRequest('update_issue', {
      'id': id,
      'updates': updates,
      'actor': actor,
    });
  }

  Future<String> createIssue(
    String title,
    String description,
    String type, {
    String? parent,
    int? priority,
    required String actor,
  }) async {
    final response = await _sendRpcRequest('create_issue', {
      'issue': {
        'title': title,
        'description': description,
        'issue_type': type,
        'priority': priority ?? 2,
        if (parent != null && parent.isNotEmpty)
          'dependencies': [
            {'depends_on_id': parent, 'type': 'parent-child'},
          ],
      },
      'actor': actor,
    });

    if (response == null) {
      throw Exception('Failed to create issue: empty response from daemon');
    }

    return response as String;
  }

  Future<HealthCheckResult> checkHealth() async {
    final result = await _sendRpcRequest('check_health', {});
    return HealthCheckResult.fromJson(result as Map<String, dynamic>);
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
      final result = await Process.run(
        _bdExecutable,
        ['version'],
        workingDirectory: workingDirectory,
        environment: macosPathEnv,
      );
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      _log.warning('Failed to get CLI version', error: e);
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
      _log.warning('Failed to read project required version', error: e);
    }
    return null;
  }

  Future<void> addDependency(
    String issueId,
    String dependsOn,
    String type, {
    required String actor,
  }) async {
    await _sendRpcRequest('add_dependency', {
      'issue_id': issueId,
      'depends_on': dependsOn,
      'type': type,
      'actor': actor,
    });
  }

  Future<void> removeDependency(
    String issueId,
    String dependsOn, {
    required String actor,
  }) async {
    await _sendRpcRequest('remove_dependency', {
      'issue_id': issueId,
      'depends_on': dependsOn,
      'actor': actor,
    });
  }

  Future<List<Map<String, dynamic>>> getComments(String issueId) async {
    final result = await _sendRpcRequest('get_comments', {'id': issueId});
    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<void> addComment(
    String issueId,
    String comment, {
    required String actor,
  }) async {
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
    await _sendRpcRequest('add_peer', {'name': name, 'url': url});
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
