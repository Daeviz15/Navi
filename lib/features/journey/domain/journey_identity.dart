/// Identifies one in-memory trip and its destination/mode revision.
///
/// IDs are local to the Riverpod container, not backend or persisted IDs. Screen
/// changes and preparation edits retain them; reset creates a new trip identity.
class JourneyIdentity {
  const JourneyIdentity({required this.tripId, this.intentRevision = 0});

  final int tripId;
  final int intentRevision;

  JourneyIdentity nextIntent() =>
      JourneyIdentity(tripId: tripId, intentRevision: intentRevision + 1);

  @override
  bool operator ==(Object other) =>
      other is JourneyIdentity &&
      tripId == other.tripId &&
      intentRevision == other.intentRevision;

  @override
  int get hashCode => Object.hash(tripId, intentRevision);

  @override
  String toString() => 'JourneyIdentity($tripId, $intentRevision)';
}
