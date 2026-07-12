import 'package:flutter_test/flutter_test.dart';
import 'package:agent_watcher/models/issue.dart';
import 'package:agent_watcher/models/ai_assistant.dart';
import 'package:agent_watcher/services/ai_assistant_service.dart';
import 'package:agent_watcher/state/settings_repository.dart';

void main() {
  group('AIAssistantService Tests', () {
    test(
      'assessProjectHealth returns null if gcpProjectId is missing',
      () async {
        final config = GenerativeModelConfig(
          id: 'test-model',
          displayName: 'Test Model',
          identifier: 'gemini-3.5-flash',
          region: 'us-central1',
        );

        final context = AIAssistantContext(
          issues: [],
          healthCheck: HealthCheckResult(status: 'ok', diagnostics: []),
          interactions: [],
        );

        final result = await AIAssistantService.assessProjectHealth(
          gcpProjectId: null,
          defaultAiModel: config,
          context: context,
        );

        expect(result, isNull);
      },
    );

    test(
      'assessProjectHealth returns null if defaultAiModel is missing',
      () async {
        final context = AIAssistantContext(
          issues: [],
          healthCheck: HealthCheckResult(status: 'ok', diagnostics: []),
          interactions: [],
        );

        final result = await AIAssistantService.assessProjectHealth(
          gcpProjectId: 'my-gcp-project',
          defaultAiModel: null,
          context: context,
        );

        expect(result, isNull);
      },
    );
  });
}
