/// The source of truth for verified establishment requirements will live here.
/// Never infer requirements from a destination string or create fake checklists.
abstract interface class RequirementsRepository {
  Future<VerifiedRequirements?> findRequirements({
    required String establishment,
    required String purpose,
  });
}

class VerifiedRequirements {
  const VerifiedRequirements({
    required this.items,
    required this.sourceUrl,
    required this.verifiedAt,
  });

  final List<String> items;
  final Uri sourceUrl;
  final DateTime verifiedAt;
}
