/// Server-owned product rules. Bounds validate the supported protocol, not defaults.
class AttackRules {
  AttackRules.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      version = j['version'] as int,
      questionsTotal = j['questions_total'] as int,
      questionSeconds = j['question_seconds'] as int,
      cooldownSeconds = j['cooldown_seconds'] as int,
      maxDamagePercent = (j['max_damage_percent'] as num).toDouble() {
    if (questionsTotal < 1 ||
        questionsTotal > 20 ||
        questionSeconds < 1 ||
        questionSeconds > 300 ||
        cooldownSeconds < 0 ||
        cooldownSeconds > 86400 ||
        !maxDamagePercent.isFinite ||
        maxDamagePercent <= 0 ||
        maxDamagePercent > 100) {
      throw const FormatException('Unsupported live attack configuration.');
    }
  }
  final String id;
  final int version, questionsTotal, questionSeconds, cooldownSeconds;
  final double maxDamagePercent;
  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'questions_total': questionsTotal,
    'question_seconds': questionSeconds,
    'cooldown_seconds': cooldownSeconds,
    'max_damage_percent': maxDamagePercent,
  };
  String get summary =>
      '$questionsTotal questions · $questionSeconds seconds each\nUp to ${healthText(maxDamagePercent)}% damage · ${cooldownSeconds == 0 ? 'no cooldown' : '${healthText(cooldownSeconds / 60)}-minute cooldown'}';
}

String healthText(num value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
