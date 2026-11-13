import '../../navigation/domain/destination_selection.dart';
import '../../navigation/domain/navigation_gateway.dart';

/// A readback becomes confirmable only after its speech has finished. The
/// controller keeps this prompt within one tapped conversation, never globally.
class DestinationReadback {
  const DestinationReadback(this.request, this.place);
  final DestinationSelectionRequest request;
  final DestinationPlace place;
}

class DestinationVoiceTurn {
  const DestinationVoiceTurn(
    this.text, {
    this.prompt,
    this.request,
    this.reject = false,
    this.followUp = true,
  });
  final String text;
  final DestinationReadback? prompt;
  final DestinationSelectionRequest? request;
  final bool reject;
  final bool followUp;
}

/// Bounded local interpretation. An LLM never invents a place ID or decides
/// that a raw destination label has been geographically confirmed.
class DestinationConfirmationPolicy {
  const DestinationConfirmationPolicy();

  DestinationVoiceTurn? resolve(
    String words, {
    required DestinationSuggestions? suggestions,
    required DestinationReadback? spokenPrompt,
  }) {
    if (suggestions == null) return null;
    final text = _normalize(words);
    final yes = RegExp(
      r"^(?:yes|yes please|yes correct|yes exactly|yes that is right|yes that s right|yes that s the one|yes that is the one|yes that is it|yeah|yep|correct|exactly|that s right|that is right|that s correct|that s it|that is it|that s the one|that is the one|that s the place|confirm that|confirm it)$",
    ).hasMatch(text);
    final no = RegExp(
      r"^(?:no|nope|no thanks|not that one|no not that one|that s wrong|wrong place|next one)$",
    ).hasMatch(text);
    final prompt =
        spokenPrompt?.request.token == suggestions.token &&
            suggestions.places.any(
              (place) => place.id == spokenPrompt?.request.placeId,
            )
        ? spokenPrompt
        : null;
    if (yes && prompt != null) {
      return DestinationVoiceTurn(
        'Confirmed: ${prompt.place.name}, ${prompt.place.address}.',
        request: prompt.request,
        followUp: false,
      );
    }
    if (no) {
      return DestinationVoiceTurn(
        prompt == null
            ? 'Which match should I check? Say an option number or choose an address on the map.'
            : 'Okay, not that place. Choose another address, or say change my destination to a more specific place.',
        request: prompt?.request,
        reject: prompt != null,
      );
    }

    final ordinal = RegExp(
      r'^(?:confirm |choose |select |i mean )?(?:(?:option|number) )?([1-5]|one|two|three|four|five|first|second|third|fourth|fifth)(?: one| option| please)?$',
    ).firstMatch(text.replaceFirst(RegExp(r'^the '), ''));
    final number = ordinal?.group(1);
    const numbers = {
      'one': 1,
      'first': 1,
      'two': 2,
      'second': 2,
      'three': 3,
      'third': 3,
      'four': 4,
      'fourth': 4,
      'five': 5,
      'fifth': 5,
    };
    final index = number == null
        ? null
        : (int.tryParse(number) ?? numbers[number])! - 1;
    if (index != null) {
      if (index >= suggestions.places.length) {
        return const DestinationVoiceTurn(
          'That option is unavailable. Choose one of the addresses shown on the map.',
        );
      }
      return _readback(suggestions, suggestions.places[index]);
    }

    final named = suggestions.places
        .where(
          (place) =>
              text == _normalize(place.name) ||
              text == 'the one at ${_normalize(place.address)}' ||
              text == 'confirm ${_normalize(place.name)}',
        )
        .toList();
    if (named.length == 1) return _readback(suggestions, named.single);
    if (named.length > 1) {
      return const DestinationVoiceTurn(
        'There is more than one matching branch. Say its option number or choose the exact address on the map.',
      );
    }
    final asksForPlace = const {
      'hi',
      'hello',
      'hi navi',
      'hey navi',
      'hello navi',
      'which place',
      'which one',
      'which destination',
      'confirm destination',
      'confirm my destination',
      'where are we going',
      'where are we heading',
      'what is the address',
      'repeat the address',
      'confirm the address',
    }.contains(text);
    if (yes || asksForPlace) {
      if (suggestions.places.isEmpty) {
        return const DestinationVoiceTurn(
          'I do not have a matching address yet. Refine it on the map, or say change my destination to a more specific place.',
        );
      }
      return _readback(suggestions, prompt?.place ?? suggestions.places.first);
    }
    return null;
  }

  DestinationVoiceTurn _readback(
    DestinationSuggestions suggestions,
    DestinationPlace place,
  ) {
    final request = DestinationSelectionRequest(
      token: suggestions.token,
      placeId: place.id,
      source: DestinationConfirmationSource.voice,
    );
    return DestinationVoiceTurn(
      'I found ${place.name}, ${place.address}. Is that the place?',
      prompt: DestinationReadback(request, place),
    );
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
}
