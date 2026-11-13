import 'local_command_router.dart';

/// Completion belongs to the conversation, not a model's follow-up flag or
/// whether an errand happens to need a checklist. Casual trips count too.
class TripConversationProgress {
  const TripConversationProgress({this.destination, this.purpose});

  final String? destination;
  final String? purpose;

  bool get complete => destination != null && purpose != null;

  TripConversationProgress apply(LocalReply reply) {
    if (reply.intent != LocalIntent.destination &&
        reply.intent != LocalIntent.purpose) {
      return this;
    }
    final nextDestination = _clean(reply.destination) ?? destination;
    final changed =
        destination != null &&
        nextDestination != null &&
        destination!.toLowerCase() != nextDestination.toLowerCase();
    return TripConversationProgress(
      destination: nextDestination,
      purpose: _clean(reply.purposeSummary) ?? (changed ? null : purpose),
    );
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
