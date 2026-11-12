/// Curated Nigerian & Lagos trip-preparation intelligence covering all major
/// reasons people leave home (Telecoms, Banking, Government/IDs, Visa/Embassies,
/// Healthcare, Airports/Trains, Corporate/Interviews, Education/Exams,
/// Markets/Tech Repair, Events, Logistics, and Casual/Social movements).
class TripPrepMatch {
  const TripPrepMatch({
    required this.purposeSummary,
    required this.spokenReply,
    this.inferredDestination,
    this.isCasual = false,
    this.checklist = const <String>[],
  });

  final String purposeSummary;
  final String spokenReply;
  final String? inferredDestination;
  final bool isCasual;
  final List<String> checklist;
}

class TripPrepKnowledge {
  const TripPrepKnowledge._();

  /// Compact Nigerian errand reference injected into the LLM system prompt so
  /// open-ended conversations use exact Nigerian rules rather than generic ones.
  static const String llmPlaybookReference = '''
Nigerian Trip-Prep Reference (use when the user shares their trip purpose):
- Telecoms (MTN, Airtel, Glo, 9mobile):
  * New SIM registration: ["NIN slip or Virtual NIN (VNIN)", "Valid Government ID card", "Cash or card for SIM pack & airtime"]
  * SIM swap / Welcome Back (lost/damaged SIM): ["NIN slip or VNIN", "SIM pack / PUK (or Court Affidavit if lost)", "Last recharge amount & 3 frequently dialed numbers", "Valid Government ID"]
  * NIN linkage / unbarring: ["11-digit NIN slip or VNIN", "Valid Government ID", "Affected phone and SIM line"]
- Banks (GTBank, Access, Zenith, UBA, FirstBank, OPay, Moniepoint):
  * Account opening / reactivation / BVN / upgrade: ["BVN & NIN slip", "Utility bill (LAWMA/PHCN not older than 3 months)", "Valid Government ID", "1-2 passport photographs"]
  * ATM card pickup / counter / dispense issue: ["Valid Government ID", "BVN / NIN", "Working phone to receive bank OTP"]
- Government & Identity (Ikoyi/Alausa/Festac Passport Office, NIMC, FRSC, LASSRA, INEC):
  * Passport capturing / renewal: ["Printed application, payment & appointment slips", "NIN slip matching exact name & DOB", "Old Passport (renewal) or Birth Certificate + LG Certificate (fresh)"]
  * Driver's license (FRSC/VIO): ["Expired Driver's License or Driving School Certificate", "NIN slip", "Payment & biometric capture printout"]
  * NIMC / NIN enrollment or modification: ["Birth Certificate or Sworn Declaration of Age", "Supporting ID card", "Remita receipt (if modifying details)"]
- Embassies & Visa Centers (VFS Global, TLScontact, US Consulate, High Commissions):
  * Visa biometrics / interview: ["International Passport (6+ months validity)", "Printed appointment letter & visa form", "Bank statements & original supporting docs", "Biometric passport photos (no laptops/large bags at gate)"]
- Healthcare & Diagnostics (LUTH, LASUTH, Reddington, Lagoon, Evercare, Medplus, Synlab):
  * Hospital / Lab visit: ["HMO card or hospital folder number", "Doctor's referral or prescription note", "Previous scan/lab results"]
- Airports, Trains & Terminals (MMIA, MMA2, Ebute Metta Train, Jibowu):
  * Domestic flight (MMA2): ["Valid Government ID matching ticket", "Flight booking ref / boarding pass", "Power bank (in hand luggage only)"]
  * International flight (MMIA): ["International Passport & Visa", "Yellow Fever card", "Return ticket printout & FX card"]
  * Train (Ebute Metta / Agege): ["NRC ticket confirmation", "Valid ID matching booking name"]
- Corporate & Job Interviews (Victoria Island, Ikoyi, Ikeja GRA, Yaba):
  * Interview / Business meeting: ["Printed copies of CV & credentials", "Valid ID card for building security gate pass", "Host contact name & floor number", "Power bank"]
- Education & Exams (UNILAG, LASU, Yabatech, IELTS, JAMB, Prometric):
  * Exam / Clearance: ["Original Passport or NIN slip (strict for IELTS/Prometric)", "Printed exam photocard / clearance slip", "Student ID & payment receipts"]
- Markets & Tech Repair (Computer Village Ikeja, Balogun, Tejuosho, Alaba, Mile 12):
  * Phone/Laptop repair or swap: ["Back up your device before leaving home", "Know your Apple ID / Google password", "Original box or receipt (if swapping)", "Charger to test device on the spot"]
  * Major market run: ["Cash in small notes (in case POS network fluctuates)", "Reusable market bag", "Power bank"]
- Events, Weddings (Owambe) & Logistics (DHL, GIG):
  * Event / Wedding: ["Access card / IV or QR ticket screenshot", "Valid ID card", "Power bank"]
  * Courier pickup/drop-off (DHL/GIG): ["Tracking / Waybill number", "Valid Government ID card"]
- Casual / Social Movements (visiting friends/family, hangout, restaurant, beach, cinema, gym, church/mosque, "just going"):
  * NEVER enforce a checklist! Set "isCasual": true and "checklist": [] and give a warm, witty companion response.
''';

  /// Returns a smart, tailored follow-up question when a destination is first
  /// locked in without an explicit purpose yet.
  static String destinationFollowUpQuestion(String destination) {
    final lower = destination.toLowerCase();
    if (RegExp(r'\b(?:mtn|airtel|glo|9mobile)\b').hasMatch(lower)) {
      return '$destination is locked in! Is it for SIM registration, SIM swap, or NIN?';
    }
    if (RegExp(
      r'\b(?:gtbank|access|zenith|firstbank|uba|bank|opay|moniepoint)\b',
    ).hasMatch(lower)) {
      return '$destination is locked in! Going for an account issue, BVN, or ATM card?';
    }
    if (RegExp(r'\b(?:passport|ikoyi passport|alausa passport)\b').hasMatch(lower)) {
      return '$destination is locked in! Going for capturing, renewal, or pickup?';
    }
    if (RegExp(r'\b(?:nimc|lassra)\b').hasMatch(lower)) {
      return '$destination is locked in! Going for NIN enrollment, update, or pickup?';
    }
    if (RegExp(r'\b(?:vfs|consulate|embassy|high commission)\b').hasMatch(lower)) {
      return '$destination is locked in! Heading for visa biometrics or an interview?';
    }
    if (RegExp(r'\b(?:frsc)\b').hasMatch(lower)) {
      return '$destination is locked in! Going for driver’s license capturing or pickup?';
    }
    if (RegExp(r'\b(?:computer village)\b').hasMatch(lower)) {
      return 'Computer Village, locked in! Going to fix a device or buy a gadget?';
    }
    if (RegExp(r'\b(?:luth|lasuth|hospital|clinic|reddington|lagoon|evercare)\b').hasMatch(lower)) {
      return '$destination is locked in! Going for an appointment, lab test, or visit?';
    }
    if (RegExp(r'\b(?:airport|mmia|mma2)\b').hasMatch(lower)) {
      return '$destination is locked in! Catching a flight or picking someone up?';
    }
    if (RegExp(r'\b(?:unilag|lasu|yabatech|university)\b').hasMatch(lower)) {
      return '$destination is locked in! Heading in for classes, clearance, or a visit?';
    }
    if (RegExp(r'\b(?:market|balogun|tejuosho|alaba|mile 12|idumota)\b').hasMatch(lower)) {
      return '$destination is locked in! What are we shopping for today?';
    }
    return '$destination is locked in! What’s taking us there today — an errand, work, or a visit?';
  }

  /// Checks whether [utterance] (combined with optional [currentDestination])
  /// describes a specific trip purpose (either an errand needing a checklist
  /// or a casual movement needing zero checklist).
  static TripPrepMatch? matchPurpose(
    String utterance, {
    String? currentDestination,
  }) {
    final combined = '${currentDestination ?? ''} $utterance'.toLowerCase();
    final lower = utterance.toLowerCase();

    // 1. Telecoms: SIM Swap / Welcome Back
    if (RegExp(
      r'\b(?:sim\s*swap|welcome\s*back|lost\s+(?:my\s+)?sim|replace\s+(?:my\s+)?sim|damaged\s+sim|retrieve\s+(?:my\s+)?(?:line|sim|number))\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'SIM Swap / Welcome Back',
        spokenReply:
            'Got it! Hold your NIN slip, Valid ID, and SIM pack. Your checklist is pinned!',
        checklist: [
          'NIN slip or Virtual NIN (VNIN)',
          'Old SIM pack / PUK (or Court Affidavit if lost)',
          'Last recharge amount & 3 frequently dialed numbers',
          'Valid Government ID card',
        ],
      );
    }

    // 2. Telecoms: New SIM Registration / NIN Linkage
    if (RegExp(
      r'\b(?:register\s+(?:a\s+)?(?:new\s+)?sim|new\s+sim|buy\s+(?:a\s+)?sim|sim\s+registration|link\s+(?:my\s+)?nin|nin\s+link|unbar|barred\s+line)\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'SIM Registration & NIN',
        spokenReply:
            'Nice! Hold your NIN slip and a Valid ID. I’ve pinned your checklist below!',
        checklist: [
          'NIN slip or Virtual NIN (VNIN)',
          'Valid Government ID card',
          'Cash or ATM card for SIM pack & activation airtime',
        ],
      );
    }

    // 3. Banking: Account Opening / Reactivation / Upgrade / BVN
    if (RegExp(
      r'\b(?:open\s+(?:an?\s+)?account|reactivate|dormant\s+account|upgrade\s+(?:my\s+)?account|bvn|bank\s+verification|statement\s+of\s+account)\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Bank Account / BVN Errand',
        spokenReply:
            'Bank run! Bring your BVN, NIN, utility bill, and ID. Checklist is on screen!',
        checklist: [
          'BVN & NIN slip',
          'Utility bill (LAWMA / PHCN not older than 3 months)',
          'Valid Government ID card',
          '1–2 passport photographs & phone for OTP',
        ],
      );
    }

    // 4. Banking: ATM Card Pickup / Dispense Error
    if (RegExp(
      r'\b(?:atm\s+card|debit\s+card|pick\s*up\s+(?:my\s+)?card|card\s+collection|dispense\s+error|failed\s+transfer|counter)\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Bank Card / Counter Service',
        spokenReply:
            'Got it! Bring your Valid ID, BVN, and phone for the counter OTP.',
        checklist: [
          'Valid Government ID card',
          'BVN & NIN details',
          'Phone with your bank-registered SIM for OTP',
        ],
      );
    }

    // 5. Passport Capturing / Renewal (Ikoyi / Alausa / Festac)
    if (RegExp(
      r'\b(?:passport\s+(?:capturing|renewal|collection|interview)|renew\s+(?:my\s+)?passport|international\s+passport|biometric\s+capture)\b',
    ).hasMatch(combined) &&
        RegExp(
          r'\b(?:captur|renew|collect|fresh|biometric|passport)\b',
        ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Passport Capturing / Renewal',
        spokenReply:
            'Sharp! Hold your appointment slip, NIN slip, and old passport or birth certificate.',
        checklist: [
          'Printed Passport application, payment & appointment slips',
          'NIN slip (matching exact name & date of birth)',
          'Old Passport (renewal) or Birth + LG Certificate (fresh)',
        ],
      );
    }

    // 6. Visa / Embassy / VFS Global
    if (RegExp(
      r'\b(?:visa|biometrics|embassy\s+interview|vfs|tlscontact|consulate)\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Visa / Embassy Appointment',
        spokenReply:
            'Big appointment! Bring your Passport, appointment printout, and bank statements.',
        checklist: [
          'International Passport (valid 6+ months)',
          'Printed Appointment Confirmation & Visa Form',
          'Original Bank Statements & supporting documents',
          'Biometric passport photos (avoid laptops/large bags at gate)',
        ],
      );
    }

    // 7. Job Interview / Corporate Meeting
    if (RegExp(
      r'\b(?:job\s+interview|interview|client\s+meeting|business\s+meeting|pitch)\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Interview / Business Meeting',
        spokenReply:
            'You’ve got this! Carry printed CVs and a valid ID for the gate pass.',
        checklist: [
          'Printed copies of CV & credentials',
          'Valid ID card (required for security gate pass)',
          'Host contact name & floor number',
          'Charged phone & power bank',
        ],
      );
    }

    // 8. Phone / Laptop Repair or Swap (Computer Village)
    if (RegExp(
      r'\b(?:fix\s+(?:my\s+)?(?:phone|laptop|screen)|repair\s+(?:my\s+)?(?:phone|laptop)|swap\s+(?:my\s+)?phone|buy\s+(?:a\s+)?(?:phone|laptop|gadget))\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Device Repair / Tech Purchase',
        spokenReply:
            'Smart move: back up your device first and bring your charger to test it!',
        checklist: [
          'Back up your phone/laptop data before leaving',
          'Apple ID / Google account password ready',
          'Original box or purchase receipt (if swapping)',
          'Charger / power bank to test before paying',
        ],
      );
    }

    // 9. Casual / Social / Relaxed Movements -> Explicitly NO checklist!
    if (RegExp(
      r'\b(?:visit(?:ing)?\s+(?:a\s+|my\s+)?(?:friend|guy|babe|family|sister|brother|mum|dad|uncle|aunt|cousin|partner)|hang(?:ing)?\s+out|chill(?:ing)?|eat(?:ing)?|dinner|lunch|date|party|beach|cinema|movie|gym|church|mosque|nothing\s+serious|just\s+going|personal|see\s+someone)\b',
    ).hasMatch(lower)) {
      return const TripPrepMatch(
        purposeSummary: 'Visiting & Social Outing',
        spokenReply:
            'Love that — nothing beats good company! Ready when you are.',
        isCasual: true,
        checklist: <String>[],
      );
    }

    return null;
  }
}

