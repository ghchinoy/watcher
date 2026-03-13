import 'dart:convert';
import 'dart:io';
import '../models/issue.dart';
import '../models/interaction.dart';

class BeadsService {
  final String workingDirectory;

  BeadsService(this.workingDirectory);

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
    final result = await Process.run('bd', [
      'export',
    ], workingDirectory: workingDirectory);

    if (result.exitCode != 0) {
      throw Exception('Failed to run bd export: ${result.stderr}');
    }

    final List<Issue> issues = [];
    final lines = const LineSplitter().convert(result.stdout as String);
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line);
        issues.add(Issue.fromJson(json));
      } catch (e) {
        // ignore invalid lines
      }
    }
    return issues;
  }

  Future<List<GraphNode>> getGraph() async {
    final result = await Process.run('bd', [
      'graph',
      '--all',
      '--json',
    ], workingDirectory: workingDirectory);

    if (result.exitCode != 0) {
      throw Exception('Failed to run bd graph: ${result.stderr}');
    }

    final String out = result.stdout as String;
    if (out.trim().isEmpty) return [];

    // Handle the case where bd outputs plain text instead of JSON
    // e.g. "No open issues found"
    if (!out.trim().startsWith('[')) {
      return [];
    }

    try {
      final List<dynamic> jsonList = jsonDecode(out);
      return jsonList.map((e) => GraphNode.fromJson(e)).toList();
    } catch (e) {
      throw Exception('Failed to parse graph JSON: $e\nOutput was: $out');
    }
  }

  Future<void> updateIssue(String id, {String? status, int? priority}) async {
    final List<String> args = ['update', id];
    if (status != null) {
      args.addAll(['--status', status]);
    }
    if (priority != null) {
      args.addAll(['--priority', priority.toString()]);
    }

    if (args.length <= 2) return; // Nothing to update

    final result = await Process.run(
      'bd',
      args,
      workingDirectory: workingDirectory,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to run bd update: ${result.stderr}');
    }
  }
}
