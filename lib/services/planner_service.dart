import 'dart:io';

class PlannerService {
  static Future<String> generatePlan(String workspacePath, String goal) async {
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

    // We use the 'plan' approval mode so the agent can read files but won't modify them
    final result = await Process.run(
      'gemini',
      ['-p', prompt, '--approval-mode', 'plan'],
      workingDirectory: workspacePath,
    );

    if (result.exitCode != 0 && result.exitCode != 2) {
      // Sometimes gemini might exit with non-zero if it thinks it failed a tool, but still output text.
      // We'll throw if it's completely empty or a massive failure.
      if (result.stdout.toString().isEmpty) {
        throw Exception('Planner failed: ${result.stderr}');
      }
    }

    return result.stdout.toString();
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

    final result = await Process.run(
      'bash',
      ['.beads/temp_plan.sh'],
      workingDirectory: workspacePath,
    );

    // Clean up
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    if (result.exitCode != 0) {
      throw Exception('Failed to execute plan: ${result.stderr}');
    }
  }

  static Future<String> assessGraph(String workspacePath) async {
    // Get the current bd export state
    final exportResult = await Process.run(
      'bd',
      ['export'],
      workingDirectory: workspacePath,
    );

    if (exportResult.exitCode != 0) {
      throw Exception('Failed to export bd data for assessment: ${exportResult.stderr}');
    }

    final String exportData = exportResult.stdout.toString();
    
    // Safety check if there are no issues
    if (exportData.trim().isEmpty) {
      return "No open issues found in the project. The graph is healthy!";
    }

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

    // We use the 'plan' approval mode so the agent can read files but won't modify them
    final result = await Process.run(
      'gemini',
      ['-p', prompt, '--approval-mode', 'plan'],
      workingDirectory: workspacePath,
    );

    if (result.exitCode != 0 && result.exitCode != 2) {
      if (result.stdout.toString().isEmpty) {
        throw Exception('Assessment failed: ${result.stderr}');
      }
    }

    final assessmentMarkdown = result.stdout.toString();

    return assessmentMarkdown;
  }

  static Future<String> generateAutoFixScript(String workspacePath, String assessmentMarkdown) async {
    final prompt = '''
  You are an expert Agile Scrum Master. Below is an AI Health Assessment of a project's issue tracker.

  Your task is to write a bash script containing EXCLUSIVELY `bd update` commands to fix the issues identified in the assessment (e.g., fixing priority inversions by changing priorities, or reparenting orphaned tasks). 

  DO NOT use `bd create`. ONLY use `bd update`.
  Output EXACTLY ONE bash script block (enclosed in ```bash ... ```).

  Assessment:
  $assessmentMarkdown
  ''';

    final result = await Process.run(
      'gemini',
      ['-p', prompt, '--approval-mode', 'plan'],
      workingDirectory: workspacePath,
    );

    if (result.exitCode != 0 && result.exitCode != 2) {
      if (result.stdout.toString().isEmpty) {
        throw Exception('Auto-fix planning failed: ${result.stderr}');
      }
    }

    return result.stdout.toString();
  }
  }
