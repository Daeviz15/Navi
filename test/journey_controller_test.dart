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

  test(
    'preparation and activation preserve identity; routing edits revise intent',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(journeyDraftProvider.notifier);
      controller.setDestination('Ikeja');
      final identity = container.read(journeyDraftProvider).identity;
      controller.setCompanionPrep(
        destination: ' IKEJA ',
        purposeSummary: 'SIM replacement',
        isCasual: false,
        checklist: ['ID'],
      );
      controller.toggleChecklistItem('ID');
      controller.setPurpose(JourneyPurpose.errand);
      controller.startTrip();
      controller.startTrip();
      expect(container.read(journeyDraftProvider).identity, identity);
      expect(container.read(journeyDraftProvider).isActive, isTrue);
      controller.setTravelMode(TravelMode.walking);
      final walking = container.read(journeyDraftProvider).identity;
      expect(walking.tripId, identity.tripId);
      expect(walking.intentRevision, identity.intentRevision + 1);
      controller.setTravelMode(TravelMode.walking);
      expect(container.read(journeyDraftProvider).identity, walking);
      controller.switchTripDestination('Yaba');
      expect(
        container.read(journeyDraftProvider).identity,
        walking.nextIntent(),
      );
      expect(container.read(journeyDraftProvider).checkedItems, isEmpty);
    },
  );

  test(
    'reset and replacement create distinct trips even for the same place',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(journeyDraftProvider.notifier);
      controller.setDestination('Ikeja');
      controller.startTrip();
      final first = container.read(journeyDraftProvider).identity;
      controller.setDestination(' IKEJA ');
      expect(container.read(journeyDraftProvider).identity, first);
      expect(container.read(journeyDraftProvider).isActive, isTrue);
      controller.reset();
      controller.setDestination('Ikeja');
      final second = container.read(journeyDraftProvider).identity;
      expect(second.tripId, isNot(first.tripId));
      expect(container.read(journeyDraftProvider).isActive, isFalse);
      controller.startTrip();
      controller.setDestination('Yaba');
      expect(
        container.read(journeyDraftProvider).identity.tripId,
        isNot(second.tripId),
      );
      expect(container.read(journeyDraftProvider).isActive, isFalse);
    },
  );

  test('an empty draft cannot activate', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(journeyDraftProvider.notifier).startTrip();
    expect(container.read(journeyDraftProvider).isActive, isFalse);
  });
}
