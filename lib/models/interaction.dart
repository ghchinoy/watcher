import 'package:json_annotation/json_annotation.dart';

part 'interaction.g.dart';

@JsonSerializable()
class Interaction {
  @JsonKey(name: 'created_at')
  final DateTime timestamp;
  final String actor;
  @JsonKey(name: 'event_type')
  final String action;
  @JsonKey(name: 'issue_id')
  final String? issueId;

  Interaction({
    required this.timestamp,
    required this.actor,
    required this.action,
    this.issueId,
  });

  factory Interaction.fromJson(Map<String, dynamic> json) =>
      _$InteractionFromJson(json);
  Map<String, dynamic> toJson() => _$InteractionToJson(this);
}
