import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../agent/agent_client.dart';
import '../agent/agent_fs.dart';
import '../agent/remote_profile.dart';
import 'i18n.dart';

/// What to tell the user about [e], in their language. The host's messages and the app's own (an [AgentError], a
/// thrown string, a [StateError] with a sentence in it) are already written for people and go through as they are;
/// the network and timeouts get a sentence that says what to do; a bug (a [TypeError], a cast that failed on data
/// the app didn't expect) never shows its Dart text: it is logged, and the user reads that something went wrong.
String friendlyError(Object? e) {
  final fallback = tr('Something went wrong. Try again.');
  switch (e) {
    case null:
      return fallback;
    case String():
      return e.trim().isEmpty ? fallback : tr(e);
    case AgentError():
      return e.message.trim().isEmpty ? fallback : trHost(e.message);
    case Cancelled():
      return tr('Cancelled');
    case TimeoutException():
      return tr('It took too long. Check the connection and try again.');
    case SocketException() || HttpException() || HandshakeException() || TlsException():
      return tr("Couldn't reach the network. Check the connection and try again.");
    case FileSystemException():
      final why = e.osError?.message.trim();
      final name = e.path == null ? '' : ' ${baseName(e.path!)}';
      return '${tr(e.message)}$name${why == null || why.isEmpty ? '' : ' ($why)'}';
    case PlatformException():
      final m = e.message?.trim();
      return m == null || m.isEmpty ? fallback : tr(m);
    case SetupCodeError():
      return trMsg(e.say);
    case FormatException():
      // A reply that wasn't what the app expected (JSON that didn't parse): its offsets mean nothing to anyone.
      debugPrint('friendlyError: $e');
      return tr("Got an answer the app couldn't read. Try again.");
    case StateError():
      return e.message.trim().isEmpty ? fallback : tr(e.message);
    case Error():
      debugPrint('friendlyError: $e\n${e.stackTrace ?? ''}');
      return fallback;
  }
  final text = '$e'.replaceFirst(RegExp(r'^Exception: '), '').trim();
  return text.isEmpty ? fallback : tr(text);
}

/// What to tell the user when connecting with a key fails (UX-03): a mistyped
/// or half-pasted key, the commonest first-run failure, must not show the
/// provider's raw HTTP reply. Statuses and JSON bodies are for a log; the
/// person reads what happened and what to do, in their language.
String keyProblem(Object e) {
  final raw = e is AgentError ? e.message : '$e';
  final lower = raw.toLowerCase();
  if (RegExp(r'^\s*(401|403)\b').hasMatch(raw) || lower.contains('invalid api key') || lower.contains('incorrect api key')) {
    return tr('The key was not accepted. Check that you copied all of it, with no spaces.');
  }
  if (lower.contains('timeout') || lower.contains('timed out') || lower.contains('aborted') || lower.contains('fetch failed')) {
    return tr('The provider did not answer. Check your connection and try again.');
  }
  if (e is AgentError && e.code == 'offline') return friendlyError(e);
  // Some other status: the number and the provider's JSON are for a log, not for a first-time user.
  if (RegExp(r'^\s*\d{3}\b').hasMatch(raw)) return tr('The provider answered with an error. Try again in a moment.');
  return e is AgentError ? tr(raw) : friendlyError(e);
}
