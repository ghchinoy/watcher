import 'package:json_annotation/json_annotation.dart';

part 'interaction.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Interaction {
  final DateTime timestamp;
  final String actor;
  final String action;
  final String? issueId;
  final Map<String, dynamic>? details;

  Interaction({
    required this.timestamp,
    required this.actor,
    required this.action,
    this.issueId,
    this.details,
  });

  factory Interaction.fromJson(Map<String, dynamic> json) => _$InteractionFromJson(json);
  Map<String, dynamic> toJson() => _$InteractionToJson(this);
}
