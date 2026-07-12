import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart' as fb_ai;
import 'package:google_generative_ai/google_generative_ai.dart' as direct_ai;
import '../models/ai_assistant.dart';
import '../state/settings_repository.dart';
import '../firebase_options.dart';
import '../utils/app_logger.dart';

class AIAssistantService {
  static final _log = AppLogger('AIAssistantService');
  static bool _initialized = false;

  static Future<void> ensureInitialized({required String? gcpProjectId}) async {
    if (_initialized) return;
    if (gcpProjectId == null || gcpProjectId.isEmpty) {
      throw Exception('GCP Project ID is required for Vertex AI initialization.');
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.getOptions(projectId: gcpProjectId),
        );
      }
      _initialized = true;
    } catch (e) {
      _log.error('Failed to initialize Firebase in AIAssistantService', error: e);
    }
  }

  /// Runs background health assessment and returns parsed AIAssistantAssessment with critique and structured recommendations.
  static Future<AIAssistantAssessment?> assessProjectHealth({
    required String? aiProvider,
    required String? gcpProjectId,
    required String? geminiApiKey,
    required GenerativeModelConfig? defaultAiModel,
    required AIAssistantContext context,
  }) async {
    final config = defaultAiModel;
    if (config == null) {
      _log.info(
        'AI configuration missing — skipping AI Assistant background assessment',
      );
      return null;
    }

    final provider = aiProvider ?? 'direct_gemini';
    if (provider == 'gcp_vertex') {
      if (gcpProjectId == null || gcpProjectId.isEmpty) {
        _log.info(
          'AI configuration missing (GCP Project ID) — skipping AI Assistant background assessment',
        );
        return null;
      }
      await ensureInitialized(gcpProjectId: gcpProjectId);
    } else if (provider == 'direct_gemini') {
      if (geminiApiKey == null || geminiApiKey.isEmpty) {
        _log.info(
          'AI configuration missing (Gemini API Key) — skipping AI Assistant background assessment',
        );
        return null;
      }
    } else {
      throw Exception('Unsupported AI provider: $provider');
    }

    try {
      final contextStr = context.toPromptString();
      final promptText = '''
You are an expert Agile Scrum Master and Project Manager.
Analyze the following project context and health check diagnostic data representing a software project graph.

$contextStr

Please perform a qualitative "Health Assessment" critique. Look for:
1. **Priority Inversions**: P2/P3 tasks blocking P0/P1 tasks.
2. **Stagnation**: Active tasks with no recent updates or in progress for too long.
3. **Orphaned Tasks**: Tasks that don't belong to any Epic/parent.
4. **Scope Creep**: Epics with excessively many open child tasks.
5. **Static Diagnostics / Cycle Errors**: Direct cycle or dependency errors from the static health check.

Output your response strictly as a JSON object matching the following structure:
{
  "narrative": "Your detailed Markdown critique of the project's health graph...",
  "recommendations": [
    {
      "title": "A human-readable recommendation action",
      "action_type": "update_priority | assign_issue | update_status | add_dependency",
      "payload": {
        "issue_id": "the-issue-id",
        ... depending on action_type ...
      }
    }
  ]
}

For each recommendation:
- "update_priority" payload format: {"issue_id": "string", "priority": integer 0-4}
- "assign_issue" payload format: {"issue_id": "string", "assignee": "string"}
- "update_status" payload format: {"issue_id": "string", "status": "todo | in_progress | in_review | closed"}
- "add_dependency" payload format: {"issue_id": "string", "depends_on_id": "string", "type": "blocks | parent-child | related | discovered-from"}

Provide high-quality, actionable recommendation items. ONLY return JSON. Do not include markdown code block backticks (e.g. ```json) around the JSON output, just the raw JSON object itself.
''';

      String? responseText;
      if (provider == 'gcp_vertex') {
        final ai = fb_ai.FirebaseAI.vertexAI(location: config.region);

        final model = ai.generativeModel(
          model: config.identifier,
          generationConfig: fb_ai.GenerationConfig(
            maxOutputTokens: 2048,
            temperature: 0.2,
            responseMimeType: 'application/json',
          ),
        );

        final response = await model.generateContent([fb_ai.Content.text(promptText)]);
        responseText = response.text;
      } else {
        final model = direct_ai.GenerativeModel(
          model: config.identifier,
          apiKey: geminiApiKey!,
          generationConfig: direct_ai.GenerationConfig(
            maxOutputTokens: 2048,
            temperature: 0.2,
            responseMimeType: 'application/json',
          ),
        );

        final response = await model.generateContent([direct_ai.Content.text(promptText)]);
        responseText = response.text;
      }

      if (responseText == null || responseText.isEmpty) {
        _log.error('Empty response from AI Assistant Gemini');
        throw Exception('AI Assistant returned an empty response.');
      }

      // Clean up the response just in case the LLM still wrapped it in backticks
      var cleanedText = responseText.trim();
      if (cleanedText.startsWith('```')) {
        final firstNewline = cleanedText.indexOf('\n');
        if (firstNewline != -1) {
          cleanedText = cleanedText.substring(firstNewline + 1);
        }
        if (cleanedText.endsWith('```')) {
          cleanedText = cleanedText.substring(0, cleanedText.length - 3);
        }
        cleanedText = cleanedText.trim();
      }

      final dynamic decoded = jsonDecode(cleanedText);
      if (decoded is! Map<String, dynamic>) {
        _log.error(
          'Response from AI Assistant Gemini is not a JSON object: $cleanedText',
        );
        throw Exception('Response is not a valid JSON object.');
      }

      return AIAssistantAssessment.fromJson(decoded);
    } catch (e) {
      _log.error('Error during background project health assessment', error: e);
      rethrow;
    }
  }
}
