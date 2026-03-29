import 'dart:io';

class TmuxService {
  static const _env = {
    'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
  };

  /// Resolves the absolute path to the tmux executable to bypass macOS GUI PATH limitations.
  static Future<String> _getTmuxPath() async {
    const paths = ['/opt/homebrew/bin/tmux', '/usr/local/bin/tmux', '/usr/bin/tmux'];
    for (final path in paths) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return 'tmux'; // Fallback
  }

  /// Checks if a tmux session with the given name exists.
  static Future<bool> hasSession(String sessionName) async {
    try {
      final tmux = await _getTmuxPath();
      final result = await Process.run(tmux, ['has-session', '-t', sessionName], environment: _env);
      return result.exitCode == 0;
    } catch (e) {
      // If tmux executable is not found, Process.run throws ProcessException
      return false;
    }
  }

  /// Creates a new detached tmux session.
  static Future<void> createSession(String sessionName, String workingDirectory) async {
    final tmux = await _getTmuxPath();
    try {
      final result = await Process.run(tmux, [
        'new-session',
        '-d',
        '-s', sessionName,
        '-c', workingDirectory
      ], environment: _env);
      if (result.exitCode != 0) {
        throw Exception('Failed to create tmux session: ${result.stderr}');
      }
    } on ProcessException {
      throw Exception('tmux is not installed or could not be found. Please install it (e.g. `brew install tmux`) to use AI Terminal Orchestration.');
    }
  }

  /// Ensures a session exists, creating it if necessary.
  static Future<void> ensureSession(String sessionName, String workingDirectory) async {
    if (!await hasSession(sessionName)) {
      await createSession(sessionName, workingDirectory);
    }
  }

  /// Sends keys (a command) to the specified tmux session and presses Enter.
  static Future<void> sendKeys(String sessionName, String command) async {
    final tmux = await _getTmuxPath();
    try {
      final result = await Process.run(tmux, [
        'send-keys',
        '-t', sessionName,
        command,
        'C-m'
      ], environment: _env);
      if (result.exitCode != 0) {
        throw Exception('Failed to send keys to tmux session: ${result.stderr}');
      }
    } on ProcessException {
      throw Exception('tmux is not installed or could not be found. Please install it (e.g. `brew install tmux`) to use AI Terminal Orchestration.');
    }
  }

  /// Launches the preferred terminal app and attaches it to the tmux session.
  static Future<void> attachInTerminal(String sessionName, {String terminalApp = 'Ghostty'}) async {
    final tmux = await _getTmuxPath();

    if (terminalApp == 'Ghostty') {
      // Ghostty can be launched with -e to execute a command
      final ghosttyPath = '/Applications/Ghostty.app/Contents/MacOS/ghostty';
      if (await File(ghosttyPath).exists()) {
        // Pass arguments individually so Ghostty doesn't treat the whole string as one executable name
        await Process.start(ghosttyPath, ['-e', tmux, 'attach', '-t', sessionName], environment: _env);
      } else {
        // Fallback if not found in standard location
        await Process.run('open', ['-a', 'Ghostty']);
      }
    } else if (terminalApp == 'iTerm2') {
      // iTerm2 AppleScript to create a new window and attach
      final script = '''
        tell application "iTerm"
          create window with default profile
          tell current session of current window
            write text "$tmux attach -t $sessionName"
          end tell
          activate
        end tell
      ''';
      await Process.run('osascript', ['-e', script]);
    } else {
      // Default to Apple's Terminal.app
      final script = '''
        tell application "Terminal"
          do script "$tmux attach -t $sessionName"
          activate
        end tell
      ''';
      await Process.run('osascript', ['-e', script]);
    }
  }
}
