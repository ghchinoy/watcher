// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'issue.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Dependency _$DependencyFromJson(Map<String, dynamic> json) => Dependency(
  issueId: json['issue_id'] as String,
  dependsOnId: json['depends_on_id'] as String,
  type: json['type'] as String,
);

Map<String, dynamic> _$DependencyToJson(Dependency instance) =>
    <String, dynamic>{
      'issue_id': instance.issueId,
      'depends_on_id': instance.dependsOnId,
      'type': instance.type,
    };

Issue _$IssueFromJson(Map<String, dynamic> json) => Issue(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  status: json['status'] as String,
  priority: (json['priority'] as num).toInt(),
  issueType: json['issue_type'] as String,
  owner: json['owner'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  createdBy: json['created_by'] as String?,
  updatedAt: DateTime.parse(json['updated_at'] as String),
  dependencyCount: (json['dependency_count'] as num?)?.toInt(),
  dependentCount: (json['dependent_count'] as num?)?.toInt(),
  commentCount: (json['comment_count'] as num?)?.toInt(),
  dependencies: (json['dependencies'] as List<dynamic>?)
      ?.map((e) => Dependency.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$IssueToJson(Issue instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'description': instance.description,
  'status': instance.status,
  'priority': instance.priority,
  'issue_type': instance.issueType,
  'owner': instance.owner,
  'created_at': instance.createdAt.toIso8601String(),
  'created_by': instance.createdBy,
  'updated_at': instance.updatedAt.toIso8601String(),
  'dependency_count': instance.dependencyCount,
  'dependent_count': instance.dependentCount,
  'comment_count': instance.commentCount,
  'dependencies': instance.dependencies,
};

GraphNode _$GraphNodeFromJson(Map<String, dynamic> json) => GraphNode(
  root: Issue.fromJson(json['Root'] as Map<String, dynamic>),
  issues: (json['Issues'] as List<dynamic>?)
      ?.map((e) => Issue.fromJson(e as Map<String, dynamic>))
      .toList(),
  dependencies: (json['Dependencies'] as List<dynamic>?)
      ?.map((e) => Dependency.fromJson(e as Map<String, dynamic>))
      .toList(),
  issueMap: (json['IssueMap'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, Issue.fromJson(e as Map<String, dynamic>)),
  ),
);

Map<String, dynamic> _$GraphNodeToJson(GraphNode instance) => <String, dynamic>{
  'Root': instance.root,
  'Issues': instance.issues,
  'Dependencies': instance.dependencies,
  'IssueMap': instance.issueMap,
};
