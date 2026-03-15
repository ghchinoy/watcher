// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Interaction _$InteractionFromJson(Map<String, dynamic> json) => Interaction(
  timestamp: DateTime.parse(json['created_at'] as String),
  actor: json['actor'] as String,
  action: json['event_type'] as String,
  issueId: json['issue_id'] as String?,
  newValue: json['new_value'] as String?,
  oldValue: json['old_value'] as String?,
  comment: json['comment'] as String?,
);

Map<String, dynamic> _$InteractionToJson(Interaction instance) =>
    <String, dynamic>{
      'created_at': instance.timestamp.toIso8601String(),
      'actor': instance.actor,
      'event_type': instance.action,
      'issue_id': instance.issueId,
      'new_value': instance.newValue,
      'old_value': instance.oldValue,
      'comment': instance.comment,
    };
