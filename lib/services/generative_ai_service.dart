import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import '../models/issue.dart';
import '../state/app_state.dart';
import '../firebase_options.dart';

class GenerativeAiService {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize Firebase: $e');
    }
  }

  static Future<String?> summarizeIssueResolution({
    required AppState appState,
    required Issue issue,
    required List<Map<String, dynamic>> comments,
    String? gitDiff,
  }) async {
    await ensureInitialized();

    if (appState.gcpProjectId == null) {
      debugPrint('GCP Project ID not configured. Skipping summarization.');
      return null;
    }

    try {
      final ai = FirebaseAI.vertexAI(
        location: appState.vertexLocation,
      );

      final model = ai.generativeModel(
        model: appState.geminiModel,
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
''')
      ];

      final response = await model.generateContent(prompt);
      return response.text?.trim();
    } catch (e) {
      debugPrint('Generative AI Error: $e');
      return null;
    }
  }
}
