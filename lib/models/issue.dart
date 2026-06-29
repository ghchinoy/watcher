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

  HealthCheckResult({required this.status, required this.diagnostics});

  factory HealthCheckResult.fromJson(Map<String, dynamic> json) =>
      _$HealthCheckResultFromJson(json);
  Map<String, dynamic> toJson() => _$HealthCheckResultToJson(this);
}

/// Readiness and blocking semantics for the 'blocks' dependency type.
///
/// Canonical direction (verified against `bd blocked` output):
///   A dependency {depends_on_id: Y, type: 'blocks'} stored on issue X
///   means "X is blocked by Y — Y must close before X is actionable."
///
/// Example from the read-aloud sister project:
///   ijo.3 carries depends_on=89j.3, type=blocks
///   → `bd blocked` reports "ijo.3: Blocked by [89j.3]"
///   → ijo.3.blockers([89j.3_open]) == [89j.3]
///   → ijo.3.isBlocked([...]) == true
extension IssueDependencies on Issue {
  /// Open issues that are blocking this one from being actionable.
  /// Computed from this issue's own [blocks] dependencies: the dep target
  /// must exist in [all] and must NOT be closed.
  List<Issue> blockers(List<Issue> all) {
    final blockerIds =
        dependencies
            ?.where((d) => d.type == 'blocks')
            .map((d) => d.dependsOnId)
            .toSet() ??
        {};
    if (blockerIds.isEmpty) return [];
    return all
        .where((i) => blockerIds.contains(i.id) && i.status != 'closed')
        .toList();
  }

  /// Issues that are waiting on this one to close before they become actionable.
  /// Reverse lookup: issues in [all] whose own [blocks] dep points at this id.
  List<Issue> blocking(List<Issue> all) {
    return all
        .where(
          (i) =>
              i.dependencies?.any(
                (d) => d.type == 'blocks' && d.dependsOnId == id,
              ) ??
              false,
        )
        .toList();
  }

  /// True if this issue has at least one open blocker.
  bool isBlocked(List<Issue> all) => blockers(all).isNotEmpty;

  /// The direct parent of this issue, or null if it is a root.
  /// Checks explicit [parent-child] dependencies first, then falls back to
  /// the dotted-ID convention (e.g. "proj-1.2" → parent is "proj-1").
  Issue? parent(List<Issue> all) {
    final explicitParentId = dependencies
        ?.where((d) => d.type == 'parent-child')
        .map((d) => d.dependsOnId)
        .firstOrNull;
    if (explicitParentId != null) {
      return all.where((i) => i.id == explicitParentId).firstOrNull;
    }
    final lastDot = id.lastIndexOf('.');
    if (lastDot != -1) {
      final implicitParentId = id.substring(0, lastDot);
      return all.where((i) => i.id == implicitParentId).firstOrNull;
    }
    return null;
  }

  /// Direct children of this issue in the parent-child hierarchy.
  List<Issue> children(List<Issue> all) {
    return all.where((i) => i.isDirectChildOf(this)).toList();
  }

  /// Issues with [related] or [discovered-from] dependency links.
  List<MapEntry<String, Issue>> relatedLinks(List<Issue> all) {
    final links = <MapEntry<String, Issue>>[];
    for (final dep in dependencies ?? []) {
      if (dep.type == 'related' || dep.type == 'discovered-from') {
        final target = all.where((i) => i.id == dep.dependsOnId).firstOrNull;
        if (target != null) links.add(MapEntry(dep.type, target));
      }
    }
    return links;
  }
}

extension IssueHierarchy on Issue {
  bool isDirectChildOf(Issue parent) {
    final explicit =
        dependencies?.any(
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

  bool hasOpenDescendant(List<Issue> issues) {
    return issues.any((child) {
      if (child.isDirectChildOf(this)) {
        if (child.status != 'closed') return true;
        return child.hasOpenDescendant(issues);
      }
      return false;
    });
  }

  bool isDescendantOf(Issue ancestor, List<Issue> allIssues) {
    Issue? current = this;
    Set<String> visited = {id};

    while (current != null) {
      if (current.isDirectChildOf(ancestor)) return true;

      String? parentId;
      final hasExplicit =
          current.dependencies?.any((d) => d.type == 'parent-child') ?? false;
      if (hasExplicit) {
        parentId = current.dependencies!
            .firstWhere((d) => d.type == 'parent-child')
            .dependsOnId;
      } else {
        final lastDotIndex = current.id.lastIndexOf('.');
        if (lastDotIndex != -1) {
          parentId = current.id.substring(0, lastDotIndex);
        }
      }

      if (parentId == null || visited.contains(parentId)) return false;

      visited.add(parentId);
      final parentIdx = allIssues.indexWhere((i) => i.id == parentId);
      current = parentIdx != -1 ? allIssues[parentIdx] : null;
    }
    return false;
  }
}
