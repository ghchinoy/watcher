import 'package:json_annotation/json_annotation.dart';

part 'issue.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Dependency {
  final String issueId;
  final String dependsOnId;
  final String type;

  Dependency({
    required this.issueId,
    required this.dependsOnId,
    required this.type,
  });

  factory Dependency.fromJson(Map<String, dynamic> json) =>
      _$DependencyFromJson(json);
  Map<String, dynamic> toJson() => _$DependencyToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Issue {
  final String id;
  final String title;
  final String? description;
  final String status;
  final int priority;
  final String issueType;
  final String? owner;
  final String? assignee;
  final String? notes;
  final DateTime createdAt;
  final String? createdBy;
  final DateTime updatedAt;
  final DateTime? closedAt;
  final String? closeReason;
  final int? dependencyCount;
  final int? dependentCount;
  final int? commentCount;
  final List<Dependency>? dependencies;

  Issue({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.issueType,
    this.owner,
    this.assignee,
    this.notes,
    required this.createdAt,
    this.createdBy,
    required this.updatedAt,
    this.closedAt,
    this.closeReason,
    this.dependencyCount,
    this.dependentCount,
    this.commentCount,
    this.dependencies,
  });

  factory Issue.fromJson(Map<String, dynamic> json) => _$IssueFromJson(json);
  Map<String, dynamic> toJson() => _$IssueToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.pascal)
class GraphNode {
  final Issue root;
  final List<Issue>? issues;
  final List<Dependency>? dependencies;
  final Map<String, Issue>? issueMap;

  GraphNode({
    required this.root,
    this.issues,
    this.dependencies,
    this.issueMap,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) =>
      _$GraphNodeFromJson(json);
  Map<String, dynamic> toJson() => _$GraphNodeToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Diagnostic {
  final String issueId;
  final String type;
  final String message;
  final String? fix;

  Diagnostic({
    required this.issueId,
    required this.type,
    required this.message,
    this.fix,
  });

  factory Diagnostic.fromJson(Map<String, dynamic> json) =>
      _$DiagnosticFromJson(json);
  Map<String, dynamic> toJson() => _$DiagnosticToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class HealthCheckResult {
  final String status;
  final List<Diagnostic> diagnostics;

  HealthCheckResult({
    required this.status,
    required this.diagnostics,
  });

  factory HealthCheckResult.fromJson(Map<String, dynamic> json) =>
      _$HealthCheckResultFromJson(json);
  Map<String, dynamic> toJson() => _$HealthCheckResultToJson(this);
}

extension IssueHierarchy on Issue {
  bool isDirectChildOf(Issue parent) {
    final explicit = dependencies?.any(
          (d) => d.type == 'parent-child' && d.dependsOnId == parent.id,
        ) ??
        false;
    final lastDotIndex = id.lastIndexOf('.');
    final implicit =
        lastDotIndex != -1 && id.substring(0, lastDotIndex) == parent.id;
    return explicit || implicit;
  }

  bool hasParentIn(List<Issue> issues) {
    final hasExplicit =
        dependencies?.any((d) => d.type == 'parent-child') ?? false;
    if (hasExplicit) return true;

    final lastDotIndex = id.lastIndexOf('.');
    if (lastDotIndex != -1) {
      final implicitParentId = id.substring(0, lastDotIndex);
      return issues.any((i) => i.id == implicitParentId);
    }
    return false;
  }
}
