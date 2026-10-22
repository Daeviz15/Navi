import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';

void main() {
  test('destination is trimmed and purpose resets on new trip', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(journeyDraftProvider.notifier);
    controller.setDestination('  Ologolo bus stop  ');
    controller.setPurpose(JourneyPurpose.errand);
    expect(
      container.read(journeyDraftProvider).destination,
      'Ologolo bus stop',
    );
    expect(container.read(journeyDraftProvider).purpose, JourneyPurpose.errand);

    controller.setDestination('Ikeja');
    expect(container.read(journeyDraftProvider).destination, 'Ikeja');
    expect(
      container.read(journeyDraftProvider).purpose,
      JourneyPurpose.unspecified,
    );
  });
}
