import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import '../models/issue.dart';
import '../state/settings_repository.dart';
import '../firebase_options.dart';
import '../utils/app_logger.dart';

class GenerativeAiService {
  static final _log = AppLogger('GenerativeAiService');
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } catch (e) {
      _log.error('Failed to initialize Firebase', error: e);
    }
  }

  static Future<String?> summarizeIssueResolution({
    required String? gcpProjectId,
    required GenerativeModelConfig? defaultAiModel,
    required Issue issue,
    required List<Map<String, dynamic>> comments,
    String? gitDiff,
  }) async {
    await ensureInitialized();

    final config = defaultAiModel;
    if (gcpProjectId == null || config == null) {
      _log.info('AI configuration missing — skipping summarization');
      return null;
    }

    try {
      final ai = FirebaseAI.vertexAI(location: config.region);

      final model = ai.generativeModel(
        model: config.identifier,
        generationConfig: GenerationConfig(
          maxOutputTokens: 250,
          temperature: 0.2,
        ),
      );

      final prompt = [
        Content.text('''
You are an expert software engineering assistant. 
Summarize the resolution of the following issue in exactly one or two concise sentences. 
Focus on *how* it was fixed based on the comments and context provided.

Issue: ${issue.id} - ${issue.title}
Description: ${issue.description}

Comments:
${comments.map((c) => "${c['author']}: ${c['text']}").join('\n')}

${gitDiff != null ? "Git Diff:\n$gitDiff" : ""}

Resolution Summary:
'''),
      ];

      final response = await model.generateContent(prompt);
      return response.text?.trim();
    } catch (e) {
      _log.error('Generative AI summarization error', error: e);
      return null;
    }
  }

  static Future<String?> generateHealthInsights({
    required String? gcpProjectId,
    required GenerativeModelConfig? defaultAiModel,
    required List<Issue> issues,
    required List<Diagnostic> diagnostics,
  }) async {
    await ensureInitialized();

    final config = defaultAiModel;
    if (gcpProjectId == null || config == null) {
      _log.info('AI configuration missing — skipping insights generation');
      return null;
    }

    try {
      final ai = FirebaseAI.vertexAI(location: config.region);

      final model = ai.generativeModel(
        model: config.identifier,
        generationConfig: GenerationConfig(
          maxOutputTokens: 1000,
          temperature: 0.2,
          responseMimeType: 'application/json',
        ),
      );

      final issuesText = issues.map((i) => '- ID: ${i.id}, Title: ${i.title}, Status: ${i.status}, Priority: ${i.priority}, Assignee: ${i.assignee}, Owner: ${i.owner}').join('\n');
      final diagnosticsText = diagnostics.isEmpty
          ? 'None. The project is completely healthy!'
          : diagnostics.map((d) => '- Issue: ${d.issueId}, Type: ${d.type}, Message: ${d.message}, Suggested Fix: ${d.fix ?? "None"}').join('\n');

      final prompt = [
        Content.text('''
You are an expert software engineering Copilot analyzing a project managed by a lightweight issue tracker called beads (bd).
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
'''),
      ];

      final response = await model.generateContent(prompt);
      String? text = response.text?.trim();
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
      return null;
    }
  }
}
