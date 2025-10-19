import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// Simple CLI to verify Google Gemini API connectivity and key validity.
// Usage:
//   dart run tool/verify_gemini_api.dart [--key=YOUR_KEY] [--model=gemini-1.5-flash-latest]
// If --key is omitted, the script will try to read from .env in the project root:
//   GEMINI_API_KEY=... or _geminiApiKey = '...'
// Exit codes: 0=success, 1=request error, 2=missing key

Future<int> main(List<String> args) async {
  // Use a lightweight available model by default
  String model = 'models/gemini-2.0-flash-lite-001';
  bool listOnly = false;
  String apiKey = '';

  for (final a in args) {
    if (a.startsWith('--key=')) {
      apiKey = a.substring('--key='.length).trim();
    } else if (a.startsWith('--model=')) {
      model = a.substring('--model='.length).trim();
    } else if (a == '--list' || a == '-l') {
      listOnly = true;
    }
  }

  if (apiKey.isEmpty) {
    apiKey = _readKeyFromEnvFile();
  }

  if (apiKey.isEmpty) {
    stderr.writeln('[verify_gemini_api] Missing API key. Provide --key or set GEMINI_API_KEY/_geminiApiKey in .env');
    return 2;
  }

  final base = 'https://generativelanguage.googleapis.com';
  final modelsList = Uri.parse('$base/v1/models');
  // normalize model name (accept either 'gemini-2.5-flash' or 'models/gemini-2.5-flash')
  final normModel = model.startsWith('models/') ? model.substring('models/'.length) : model;
  final endpoint = Uri.parse('$base/v1/models/$normModel:generateContent');

  if (listOnly) {
    stdout.writeln('[verify_gemini_api] Listing models: $modelsList');
    try {
      final resp = await http.get(modelsList, headers: {
        'x-goog-api-key': apiKey,
      }).timeout(const Duration(seconds: 15));
      stdout.writeln('[verify_gemini_api] HTTP ${resp.statusCode}');
      stdout.writeln(resp.body);
      return resp.statusCode == 200 ? 0 : 1;
    } catch (e) {
      stderr.writeln('[verify_gemini_api] List models failed: $e');
      return 1;
    }
  }

  final body = {
    'contents': [
      {
        'parts': [
          {'text': 'Reply with a single word: OK'}
        ]
      }
    ],
    'generationConfig': {
      'temperature': 0.1,
      'maxOutputTokens': 5,
    }
  };

  stdout.writeln('[verify_gemini_api] Testing model="$model" endpoint: $endpoint');
  try {
    final resp = await http
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    stdout.writeln('[verify_gemini_api] HTTP ${resp.statusCode}');

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final candidates = data is Map ? data['candidates'] : null;
      if (candidates is List && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content is Map ? content['parts'] : null;
        final text = (parts is List && parts.isNotEmpty)
            ? (parts[0]['text']?.toString() ?? '')
            : '';
        stdout.writeln('[verify_gemini_api] Response text: ${text.trim()}');
        stdout.writeln('[verify_gemini_api] SUCCESS');
        return 0;
      } else {
        stdout.writeln('[verify_gemini_api] 200 OK but empty candidates. Full body:');
        stdout.writeln(resp.body);
        return 1;
      }
    } else {
      stdout.writeln('[verify_gemini_api] ERROR body:');
      stdout.writeln(resp.body);
      _printHints(resp.statusCode, resp.body);
      return 1;
    }
  } catch (e) {
    stderr.writeln('[verify_gemini_api] Request failed: $e');
    return 1;
  }
}

String _readKeyFromEnvFile() {
  try {
    final file = File('.env');
    if (!file.existsSync()) return '';
    final raw = file.readAsStringSync();
    final lines = raw.split(RegExp(r'\r?\n'));
    for (var l in lines) {
      final line = l.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
      // Support: GEMINI_API_KEY=..., GEMINI_API_KEY: '...', _geminiApiKey = '...'
      final keyNames = ['GEMINI_API_KEY', '_geminiApiKey'];
      for (final name in keyNames) {
        if (line.startsWith('$name=') || line.startsWith('$name =') ||
            line.startsWith('$name:')) {
          var val = line.substring(line.indexOf(RegExp(r'[=:]')) + 1).trim();
          // strip inline comments // ... or # ...
          final ci = _firstIndexOfAny(val, ['//', '#']);
          if (ci != -1) {
            val = val.substring(0, ci).trim();
          }
          // drop trailing semicolon/comma
          while (val.endsWith(';') || val.endsWith(',')) {
            val = val.substring(0, val.length - 1).trim();
          }
          if (val.endsWith(',')) val = val.substring(0, val.length - 1).trim();
          if ((val.startsWith('"') && val.endsWith('"')) ||
              (val.startsWith("'") && val.endsWith("'"))) {
            val = val.substring(1, val.length - 1).trim();
          }
          return val;
        }
      }
    }
  } catch (_) {}
  return '';
}

int _firstIndexOfAny(String s, List<String> needles) {
  int best = -1;
  for (final n in needles) {
    final i = s.indexOf(n);
    if (i != -1) {
      best = best == -1 ? i : (i < best ? i : best);
    }
  }
  return best;
}

void _printHints(int status, String body) {
  // Print quick hints for common errors
  stdout.writeln('[verify_gemini_api] Hints:');
  if (status == 401 || status == 403) {
    stdout.writeln('- Check API key validity and project access.');
    stdout.writeln('- Ensure Generative Language API is enabled for your project.');
  } else if (status == 429) {
    stdout.writeln('- Quota exceeded. Check usage/quota in Google AI Studio.');
  } else if (status == 404) {
    stdout.writeln('- Verify model name and endpoint path.');
  } else if (status == 400) {
    stdout.writeln('- Invalid request. The response body typically explains the field.');
  }
  // Also show first ~500 chars for quick inspection
  final preview = body.length > 500 ? body.substring(0, 500) + ' ...' : body;
  stdout.writeln('[verify_gemini_api] Body preview: $preview');
}
