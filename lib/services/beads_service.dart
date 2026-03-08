import 'dart:convert';
import 'dart:io';
import '../models/issue.dart';

class BeadsService {
  final String workingDirectory;

  BeadsService(this.workingDirectory);

  Future<List<Issue>> getIssues() async {
    final result = await Process.run(
      'bd',
      ['export'],
      workingDirectory: workingDirectory,
    );

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
    final result = await Process.run(
      'bd',
      ['graph', '--all', '--json'],
      workingDirectory: workingDirectory,
    );

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
}
