import 'package:flutter_test/flutter_test.dart';
import 'package:agent_watcher/services/planner_service.dart';

void main() {
  group('PlannerService _tokenize', () {
    test('splits on unquoted whitespace', () {
      final tokens = PlannerService.tokenize('bd create "hello world"');
      expect(tokens, ['bd', 'create', 'hello world']);
    });

    test('handles single quotes', () {
      final tokens = PlannerService.tokenize("bd create 'hello world'");
      expect(tokens, ['bd', 'create', 'hello world']);
    });

    test('handles escaped quotes and backslashes', () {
      final tokens = PlannerService.tokenize('bd create "hello \\"world\\""');
      expect(tokens, ['bd', 'create', 'hello "world"']);
    });

    test('handles backslash escapes outside quotes', () {
      final tokens = PlannerService.tokenize('bd\\ create issue');
      expect(tokens, ['bd create', 'issue']);
    });

    test('leaves unquoted shell metacharacters as literal tokens', () {
      // Shell metacharacters like ; & | should just be normal tokens
      // because they are never parsed/run by shell.
      final tokens = PlannerService.tokenize('bd create "x"; touch /tmp/pwned');
      expect(tokens, ['bd', 'create', 'x;', 'touch', '/tmp/pwned']);
    });
  });

  group('PlannerService _parseBdCommands', () {
    test('parses valid bd commands correctly', () {
      final block = '''
bd create "Epic issue" --type epic
bd create "Task issue" --type task --parent bd-1
''';
      final commands = PlannerService.parseBdCommands(block);
      expect(commands.length, 2);
      expect(commands[0], ['create', 'Epic issue', '--type', 'epic']);
      expect(commands[1], ['create', 'Task issue', '--type', 'task', '--parent', 'bd-1']);
    });

    test('ignores comments and empty lines', () {
      final block = '''
# This is a comment
bd create "Epic"

# Another comment
bd update bd-1 --priority 1
''';
      final commands = PlannerService.parseBdCommands(block);
      expect(commands.length, 2);
      expect(commands[0], ['create', 'Epic']);
      expect(commands[1], ['update', 'bd-1', '--priority', '1']);
    });

    test('supports backslash line continuation', () {
      final block = '''
bd create "Epic" \\
  --type epic \\
  --priority 0
''';
      final commands = PlannerService.parseBdCommands(block);
      expect(commands.length, 1);
      expect(commands[0], ['create', 'Epic', '--type', 'epic', '--priority', '0']);
    });

    test('rejects non-bd commands', () {
      final block = 'rm -rf /';
      expect(() => PlannerService.parseBdCommands(block), throwsException);
    });

    test('rejects disallowed subcommands', () {
      final block = 'bd onboard';
      expect(() => PlannerService.parseBdCommands(block), throwsException);
    });

    test('rejects command injection attempt with semicolon', () {
      final block = 'bd create "x"; touch /tmp/pwned';
      // Semicolon splits unquoted space but first token must be bd and second allowed subcommand,
      // which is 'create'. However, when it splits, it will treat it as a single line,
      // tokenized as: ['bd', 'create', 'x;', 'touch', '/tmp/pwned'].
      // This is a single command call, but wait, the argv returned by parseBdCommands is:
      // ['create', 'x;', 'touch', '/tmp/pwned'].
      // Since it's run via Process.run directly with this argv, the semicolon is NOT
      // interpreted by shell, it is passed directly as a literal parameter 'x;' to bd.
      // So no command injection happens.
      final commands = PlannerService.parseBdCommands(block);
      expect(commands.length, 1);
      expect(commands[0], ['create', 'x;', 'touch', '/tmp/pwned']);
    });

    test('rejects multi-statement injection attempt via newlines', () {
      // If injection tries to use a newline to inject a non-bd command:
      final block = '''
bd create "x"
rm -rf /
''';
      expect(() => PlannerService.parseBdCommands(block), throwsException);
    });

    test('rejects multi-statement injection attempt via non-allowed bd commands on newlines', () {
      // If injection tries to use a newline to run 'bd config':
      final block = '''
bd create "x"
bd config set some-key
''';
      expect(() => PlannerService.parseBdCommands(block), throwsException);
    });
  });
}
