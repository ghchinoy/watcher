import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'beads_service.dart';
import 'tmux_service.dart';
import '../utils/app_logger.dart';

class PlannerService {
  static final _log = AppLogger('PlannerService');
  static Future<void> startGeneratePlan({
    required String workspacePath,
    required String goal,
    required String sessionName,
    required String terminalApp,
    String? ghosttyTheme,
    String? ghosttyFontFamily,
    String customBdPath = '',
  }) async {
    final prompt =
        '''
You are an expert AI Project Manager and Planner.
The user wants to accomplish the following goal in the current workspace: "$goal"

Please analyze the codebase to understand the context. Then, propose a structured plan of Epics and Tasks to achieve this goal.
Include:
1. A brief rationale for your plan.
2. Any critical questions or considerations.
3. EXACTLY ONE bash script block (enclosed in ```bash ... ```) containing the 'bd create' commands necessary to create this plan in the local issue tracker. 
Make sure to use '--parent' to nest tasks under epics, and use '--type epic' and '--type task'. Assign reasonable priorities (-p 0-4).

Do NOT use markdown TODOs or other tracking methods, ONLY output the bd commands.
''';

    // 1. Write the prompt to a temp file to avoid complex shell escaping in tmux send-keys
    final promptFile = File('$workspacePath/.beads/ai_prompt.txt');
    await promptFile.writeAsString(prompt);

    // 2. Clean up previous run files if they exist
    final doneFile = File('$workspacePath/.beads/ai_done');
    final outFile = File('$workspacePath/.beads/ai_out.md');
    if (doneFile.existsSync()) await doneFile.delete();
    if (outFile.existsSync()) await outFile.delete();

    // 3. Ensure the tmux session exists
    await TmuxService.ensureSession(sessionName, workspacePath);

    // 4. Construct the shell pipeline to run inside tmux
    // It reads the prompt file, runs gemini, tees the output, and writes the lockfile when done
    final command =
        'gemini -p "\$(cat .beads/ai_prompt.txt)" --approval-mode plan | tee .beads/ai_out.md; touch .beads/ai_done';

    // 5. Send keys to the tmux session
    await TmuxService.sendKeys(sessionName, command);

    // 6. Launch the preferred terminal to show the session
    await TmuxService.attachInTerminal(
      sessionName,
      terminalApp: terminalApp,
      ghosttyTheme: ghosttyTheme,
      ghosttyFontFamily: ghosttyFontFamily,
    );
  }

  static Future<String> pollForCompletion(String workspacePath) async {
    final doneFile = File('$workspacePath/.beads/ai_done');
    final outFile = File('$workspacePath/.beads/ai_out.md');

    // Poll every second until ai_done exists
    while (!doneFile.existsSync()) {
      await Future.delayed(const Duration(seconds: 1));
    }

    // Read the output
    String result = '';
    if (outFile.existsSync()) {
      result = await outFile.readAsString();
    }

    // Clean up temp files
    try {
      await doneFile.delete();
      await outFile.delete();
      final promptFile = File('$workspacePath/.beads/ai_prompt.txt');
      if (promptFile.existsSync()) await promptFile.delete();
    } catch (e) {
      _log.debug('Temp AI file cleanup failed (non-critical)', error: e);
    }

    return result;
  }

  /// Subcommands the planner/auto-fix flows are permitted to run. Anything
  /// else in the LLM output is rejected rather than executed.
  static const _allowedBdSubcommands = {'create', 'update', 'dep'};

  /// Parses the `bd` commands from an LLM planner/auto-fix response and executes
  /// them **without a shell**.
  ///
  /// SECURITY (SEC-01): the previous implementation wrote the LLM-authored bash
  /// block to `.beads/temp_plan.sh` and ran it via `bash`, which is arbitrary
  /// remote code execution the moment a prompt/issue/repo can influence the
  /// model output. We now tokenize each line ourselves, require the first token
  /// to be `bd` with an allow-listed subcommand, and invoke the resolved `bd`
  /// binary directly with an argument vector — no shell, no temp file, so shell
  /// metacharacters (`;`, `|`, `$(...)`, backticks, `&&`, redirects) are inert.
  static Future<void> executeScript(
    String workspacePath,
    String script, {
    String customBdPath = '',
  }) async {
    // Extract the script block from the markdown (kept as ```bash for prompt
    // compatibility; the contents are parsed, never handed to a shell).
    final regex = RegExp(r'```(?:bash|sh)?\n(.*?)\n```', dotAll: true);
    final match = regex.firstMatch(script);

    if (match == null) {
      throw Exception('No command block found in the planner response.');
    }

    final commands = _parseBdCommands(match.group(1)!);
    if (commands.isEmpty) {
      throw Exception(
        'No runnable `bd` commands were found in the planner response.',
      );
    }

    final bdPath = await _resolveBdPath(customBdPath);

    final failures = <String>[];
    for (final args in commands) {
      final result = await Process.run(
        bdPath,
        args,
        workingDirectory: workspacePath,
        environment: {'PATH': macosDefaultPath},
      );
      if (result.exitCode != 0) {
        failures.add('bd ${args.join(' ')} -> ${result.stderr}'.trim());
      }
    }

    if (failures.isNotEmpty) {
      throw Exception('Failed to execute plan:\n${failures.join('\n')}');
    }
  }

  /// Splits an LLM script block into a list of validated `bd` argument vectors.
  ///
  /// - Blank lines, comments (`#...`) and shell line-continuations are handled.
  /// - Each logical line is tokenized with [_tokenize] (POSIX-ish quoting).
  /// - The first token MUST be `bd` (any leading absolute path is stripped) and
  ///   the subcommand MUST be in [_allowedBdSubcommands]; anything else throws.
  static List<List<String>> _parseBdCommands(String block) {
    final commands = <List<String>>[];

    // Join backslash line-continuations so multi-line `bd create ... \` works.
    final logicalLines = block
        .replaceAll('\\\n', ' ')
        .split('\n');

    for (final raw in logicalLines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final tokens = _tokenize(line);
      if (tokens.isEmpty) continue;

      // Normalize the executable token: accept `bd`, `/abs/path/bd`, or the
      // user's configured bd path; reject anything else outright.
      final exe = tokens.first;
      final exeName = exe.split('/').last;
      if (exeName != 'bd') {
        throw Exception(
          'Refusing to run non-bd command from planner output: "$exe". '
          'Only `bd` commands are permitted.',
        );
      }

      if (tokens.length < 2 || !_allowedBdSubcommands.contains(tokens[1])) {
        final sub = tokens.length < 2 ? '(none)' : tokens[1];
        throw Exception(
          'Refusing to run disallowed bd subcommand "$sub". '
          'Allowed: ${_allowedBdSubcommands.join(', ')}.',
        );
      }

      // Drop the executable token; keep the subcommand + its args as the vector.
      commands.add(tokens.sublist(1));
    }

    return commands;
  }

  /// Minimal POSIX-style tokenizer: splits on unquoted whitespace and honors
  /// single quotes, double quotes and backslash escaping. Because the result is
  /// passed to [Process.run] as an argv (never to a shell), unquoted shell
  /// metacharacters carry no special meaning and cannot inject extra commands.
  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var hasToken = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];

      if (inSingle) {
        if (ch == "'") {
          inSingle = false;
        } else {
          buf.write(ch);
        }
        continue;
      }

      if (inDouble) {
        if (ch == '\\' && i + 1 < input.length) {
          final next = input[i + 1];
          // In double quotes only these are escapes; otherwise keep backslash.
          if (next == '"' || next == '\\' || next == r'$' || next == '`') {
            buf.write(next);
            i++;
          } else {
            buf.write(ch);
          }
        } else if (ch == '"') {
          inDouble = false;
        } else {
          buf.write(ch);
        }
        continue;
      }

      // Unquoted context.
      if (ch == "'") {
        inSingle = true;
        hasToken = true;
      } else if (ch == '"') {
        inDouble = true;
        hasToken = true;
      } else if (ch == '\\' && i + 1 < input.length) {
        buf.write(input[i + 1]);
        i++;
        hasToken = true;
      } else if (ch == ' ' || ch == '\t') {
        if (hasToken) {
          tokens.add(buf.toString());
          buf.clear();
          hasToken = false;
        }
      } else {
        buf.write(ch);
        hasToken = true;
      }
    }

    if (hasToken) tokens.add(buf.toString());
    return tokens;
  }

  /// Resolves the absolute path to the `bd` executable, preferring the user's
  /// configured override, then standard Homebrew/system locations.
  static Future<String> _resolveBdPath(String customBdPath) async {
    if (customBdPath.isNotEmpty && await File(customBdPath).exists()) {
      return customBdPath;
    }
    const candidates = [
      '/opt/homebrew/bin/bd',
      '/usr/local/bin/bd',
      '/usr/bin/bd',
    ];
    for (final c in candidates) {
      if (await File(c).exists()) return c;
    }
    return 'bd'; // last resort; PATH is set on the Process.run call
  }

  static Future<bool> startAssessGraph({
    required String workspacePath,
    required String sessionName,
    required String terminalApp,
    required BeadsService beadsService,
    String? ghosttyTheme,
    String? ghosttyFontFamily,
    String customBdPath = '',
  }) async {
    // Get the current bd export state via the internal daemon
    final issues = await beadsService.getIssues();

    // Safety check if there are no issues
    if (issues.isEmpty) {
      return false; // Indicates no work needed
    }

    // Convert issues back to JSONL for the prompt
    final exportData = issues.map((i) => jsonEncode(i.toJson())).join('\n');

    final prompt =
        '''
You are an expert Agile Scrum Master and Project Manager.
Analyze the following JSONL output from the `bd` issue tracker for a software project.

Assess the "Health" of this project graph. Look for the following specific anti-patterns:
1. **Priority Inversions**: Are there P2 or P3 tasks that are blocking P0 or P1 tasks?
2. **Stagnation**: Are there issues that have been in 'in_progress' for a long time compared to their peers?
3. **Orphaned Tasks**: Are there isolated tasks that should probably belong to an Epic?
4. **Scope Creep**: Does an Epic have a suspiciously large number of open tasks compared to others?

Provide a concise, highly readable Markdown report summarizing your findings. Use bullet points and bold text for emphasis. Do not write any code or scripts, just the analysis.

JSONL Data:
$exportData
''';

    // 1. Write prompt
    final promptFile = File('$workspacePath/.beads/ai_prompt.txt');
    await promptFile.writeAsString(prompt);

    // 2. Clean up
    final doneFile = File('$workspacePath/.beads/ai_done');
    final outFile = File('$workspacePath/.beads/ai_out.md');
    if (doneFile.existsSync()) await doneFile.delete();
    if (outFile.existsSync()) await outFile.delete();

    // 3. Ensure session
    await TmuxService.ensureSession(sessionName, workspacePath);

    // 4. Command
    final command =
        'gemini -p "\$(cat .beads/ai_prompt.txt)" --approval-mode plan | tee .beads/ai_out.md; touch .beads/ai_done';

    // 5. Run & Attach
    await TmuxService.sendKeys(sessionName, command);
    await TmuxService.attachInTerminal(
      sessionName,
      terminalApp: terminalApp,
      ghosttyTheme: ghosttyTheme,
      ghosttyFontFamily: ghosttyFontFamily,
    );

    return true; // Indicates work started
  }

  static Future<void> startGenerateAutoFixScript({
    required String workspacePath,
    required String assessmentMarkdown,
    required String sessionName,
    required String terminalApp,
    String? ghosttyTheme,
    String? ghosttyFontFamily,
    String customBdPath = '',
  }) async {
    final prompt =
        '''
  You are an expert Agile Scrum Master. Below is an AI Health Assessment of a project's issue tracker.

  Your task is to write a bash script containing EXCLUSIVELY `bd update` commands to fix the issues identified in the assessment (e.g., fixing priority inversions by changing priorities, or reparenting orphaned tasks). 

  DO NOT use `bd create`. ONLY use `bd update`.
  Output EXACTLY ONE bash script block (enclosed in ```bash ... ```).

  Assessment:
  $assessmentMarkdown
  ''';

    // 1. Write prompt
    final promptFile = File('$workspacePath/.beads/ai_prompt.txt');
    await promptFile.writeAsString(prompt);

    // 2. Clean up
    final doneFile = File('$workspacePath/.beads/ai_done');
    final outFile = File('$workspacePath/.beads/ai_out.md');
    if (doneFile.existsSync()) await doneFile.delete();
    if (outFile.existsSync()) await outFile.delete();

    // 3. Ensure session
    await TmuxService.ensureSession(sessionName, workspacePath);

    // 4. Command
    final command =
        'gemini -p "\$(cat .beads/ai_prompt.txt)" --approval-mode plan | tee .beads/ai_out.md; touch .beads/ai_done';

    // 5. Run & Attach
    await TmuxService.sendKeys(sessionName, command);
    await TmuxService.attachInTerminal(
      sessionName,
      terminalApp: terminalApp,
      ghosttyTheme: ghosttyTheme,
      ghosttyFontFamily: ghosttyFontFamily,
    );
  }
}
