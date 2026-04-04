import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'beads_service.dart';
import 'tmux_service.dart';

class PlannerService {
  static Future<void> startGeneratePlan({
    required String workspacePath,
    required String goal,
    required String sessionName,
    required String terminalApp,
    String? ghosttyTheme,
    String? ghosttyFontFamily,
  }) async {
    final prompt = '''
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
    final command = 'gemini -p "\$(cat .beads/ai_prompt.txt)" --approval-mode plan | tee .beads/ai_out.md; touch .beads/ai_done';
    
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
    } catch (_) {}

    return result;
  }

  static Future<void> executeScript(String workspacePath, String script) async {
    // Extract the bash script from the markdown
    final regex = RegExp(r'```bash\n(.*?)\n```', dotAll: true);
    final match = regex.firstMatch(script);

    if (match == null) {
      throw Exception('No bash script block found in the planner response.');
    }

    final bashCommands = match.group(1)!;

    // Write to a temporary file to execute
    final tempFile = File('$workspacePath/.beads/temp_plan.sh');
    await tempFile.writeAsString(bashCommands);

    final result = await Process.run('bash', [
      '.beads/temp_plan.sh',
    ], workingDirectory: workspacePath);

    // Clean up
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    if (result.exitCode != 0) {
      throw Exception('Failed to execute plan: ${result.stderr}');
    }
  }

  static Future<bool> startAssessGraph({
    required String workspacePath,
    required String sessionName,
    required String terminalApp,
    required BeadsService beadsService,
    String? ghosttyTheme,
    String? ghosttyFontFamily,
  }) async {
    // Get the current bd export state via the internal daemon
    final issues = await beadsService.getIssues();

    // Safety check if there are no issues
    if (issues.isEmpty) {
      return false; // Indicates no work needed
    }

    // Convert issues back to JSONL for the prompt
    final exportData = issues.map((i) => jsonEncode(i.toJson())).join('\n');

    final prompt = '''
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
    final command = 'gemini -p "\$(cat .beads/ai_prompt.txt)" --approval-mode plan | tee .beads/ai_out.md; touch .beads/ai_done';
    
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
  }) async {
    final prompt = '''
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
    final command = 'gemini -p "\$(cat .beads/ai_prompt.txt)" --approval-mode plan | tee .beads/ai_out.md; touch .beads/ai_done';
    
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
