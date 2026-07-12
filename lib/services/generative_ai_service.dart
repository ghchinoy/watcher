import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart' as fb_ai;
import 'package:google_generative_ai/google_generative_ai.dart' as direct_ai;
import '../models/issue.dart';
import '../state/settings_repository.dart';
import '../firebase_options.dart';
import '../utils/app_logger.dart';

class GenerativeAiService {
  static final _log = AppLogger('GenerativeAiService');
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
      _log.error('Failed to initialize Firebase', error: e);
    }
  }

  static Future<String?> summarizeIssueResolution({
    required String? aiProvider,
    required String? gcpProjectId,
    required String? geminiApiKey,
    required GenerativeModelConfig? defaultAiModel,
    required Issue issue,
    required List<Map<String, dynamic>> comments,
    String? gitDiff,
  }) async {
    final config = defaultAiModel;
    if (config == null) {
      _log.info('AI configuration missing — skipping summarization');
      return null;
    }

    final provider = aiProvider ?? 'direct_gemini';
    if (provider == 'gcp_vertex') {
      if (gcpProjectId == null || gcpProjectId.isEmpty) {
        _log.info('AI configuration missing (GCP Project ID) — skipping summarization');
        return null;
      }
      await ensureInitialized(gcpProjectId: gcpProjectId);
    } else if (provider == 'direct_gemini') {
      if (geminiApiKey == null || geminiApiKey.isEmpty) {
        _log.info('AI configuration missing (Gemini API Key) — skipping summarization');
        return null;
      }
    } else {
      throw Exception('Unsupported AI provider: $provider');
    }

    try {
      final promptText = '''
You are an expert software engineering assistant. 
Summarize the resolution of the following issue in exactly one or two concise sentences. 
Focus on *how* it was fixed based on the comments and context provided.

Issue: ${issue.id} - ${issue.title}
Description: ${issue.description}

Comments:
${comments.map((c) => "${c['author']}: ${c['text']}").join('\n')}

${gitDiff != null ? "Git Diff:\n$gitDiff" : ""}

Resolution Summary:
''';

      String? responseText;
      if (provider == 'gcp_vertex') {
        final ai = fb_ai.FirebaseAI.vertexAI(location: config.region);

        final model = ai.generativeModel(
          model: config.identifier,
          generationConfig: fb_ai.GenerationConfig(
            maxOutputTokens: 250,
            temperature: 0.2,
          ),
        );

        final response = await model.generateContent([fb_ai.Content.text(promptText)]);
        responseText = response.text;
      } else {
        final model = direct_ai.GenerativeModel(
          model: config.identifier,
          apiKey: geminiApiKey!,
          generationConfig: direct_ai.GenerationConfig(
            maxOutputTokens: 250,
            temperature: 0.2,
          ),
        );

        final response = await model.generateContent([direct_ai.Content.text(promptText)]);
        responseText = response.text;
      }

      return responseText?.trim();
    } catch (e) {
      _log.error('Generative AI summarization error', error: e);
      return null;
    }
  }

  static Future<String?> generateHealthInsights({
    required String? aiProvider,
    required String? gcpProjectId,
    required String? geminiApiKey,
    required GenerativeModelConfig? defaultAiModel,
    required List<Issue> issues,
    required List<Diagnostic> diagnostics,
  }) async {
    final config = defaultAiModel;
    if (config == null) {
      _log.info('AI configuration missing — skipping insights generation');
      return null;
    }

    final provider = aiProvider ?? 'direct_gemini';
    if (provider == 'gcp_vertex') {
      if (gcpProjectId == null || gcpProjectId.isEmpty) {
        _log.info('AI configuration missing (GCP Project ID) — skipping insights generation');
        return null;
      }
      await ensureInitialized(gcpProjectId: gcpProjectId);
    } else if (provider == 'direct_gemini') {
      if (geminiApiKey == null || geminiApiKey.isEmpty) {
        _log.info('AI configuration missing (Gemini API Key) — skipping insights generation');
        return null;
      }
    } else {
      throw Exception('Unsupported AI provider: $provider');
    }

    try {
      final issuesText = issues.map((i) => '- ID: ${i.id}, Title: ${i.title}, Status: ${i.status}, Priority: ${i.priority}, Assignee: ${i.assignee}, Owner: ${i.owner}').join('\n');
      final diagnosticsText = diagnostics.isEmpty
          ? 'None. The project is completely healthy!'
          : diagnostics.map((d) => '- Issue: ${d.issueId}, Type: ${d.type}, Message: ${d.message}, Suggested Fix: ${d.fix ?? "None"}').join('\n');

      final promptText = '''
You are an expert software engineering AI Assistant analyzing a project managed by a lightweight issue tracker called beads (bd).
Your task is to analyze the project's issue list and the static diagnostics/issues produced by the structural health checker.
Using these, generate a beautiful, qualitative health summary and a list of recommended next actions that are actionable and can be executed via mutations.

Current Issues in Project:
$issuesText

Static Health Check Diagnostics (Hard Factual Constraints):
$diagnosticsText

Return a JSON object matching this schema:
{
  "summary": "A friendly, cohesive, human-like narrative (2-3 sentences) summarizing the project health, explaining key bottlenecks, circular dependencies, or high-priority issues that need attention.",
  "recommendations": [
    {
      "title": "A short, concise, actionable title for the recommended action (e.g., 'Resolve circular dependency between task A and B' or 'Assign high-priority bug watcher-12 to ghchinoy')",
      "description": "A brief explanation of why this action is recommended and what it will accomplish.",
      "actionType": "updateIssue | addDependency | removeDependency | createIssue",
      "payload": {
        // For updateIssue:
        // "id": "issue-id" (required), and optionally: "status", "priority", "owner", "assignee", "parent"
        // For addDependency:
        // "issueId": "issue-id", "dependsOn": "depends-on-id", "type": "blocks"
        // For removeDependency:
        // "issueId": "issue-id", "dependsOn": "depends-on-id"
        // For createIssue:
        // "title": "...", "description": "...", "type": "bug|task|feature", "parent": "...", "priority": ...
      }
    }
  ]
}

Only return valid JSON following the schema. Do not return any markdown markdown-wrapping around the JSON, just the JSON string itself.
''';

      String? responseText;
      if (provider == 'gcp_vertex') {
        final ai = fb_ai.FirebaseAI.vertexAI(location: config.region);

        final model = ai.generativeModel(
          model: config.identifier,
          generationConfig: fb_ai.GenerationConfig(
            maxOutputTokens: 2048, // HIG-FIX: expanded from 1000 to prevent JSON truncation
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

      String? text = responseText?.trim();
      if (text != null) {
        if (text.startsWith('```json')) {
          text = text.substring(7);
        } else if (text.startsWith('```')) {
          text = text.substring(3);
        }
        if (text.endsWith('```')) {
          text = text.substring(0, text.length - 3);
        }
        text = text.trim();
      }
      return text;
    } catch (e) {
      _log.error('Generative AI health insights error', error: e);
      rethrow; // HIG-FIX: rethrow the actual exception so it bubbles up to the UI instead of swallowing it
    }
  }
}
