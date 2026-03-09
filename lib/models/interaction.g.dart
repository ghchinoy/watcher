// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Interaction _$InteractionFromJson(Map<String, dynamic> json) => Interaction(
  timestamp: DateTime.parse(json['timestamp'] as String),
  actor: json['actor'] as String,
  action: json['action'] as String,
  issueId: json['issue_id'] as String?,
  details: json['details'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$InteractionToJson(Interaction instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp.toIso8601String(),
      'actor': instance.actor,
      'action': instance.action,
      'issue_id': instance.issueId,
      'details': instance.details,
    };
