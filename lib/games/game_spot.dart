import '../map/campus_geography.dart';
import '../teams/game_team.dart';
import 'game_rules.dart';

// Shared GPS safety and invitation hysteresis; live point radii come from data.
abstract final class ProximitySettings {
  static const entryMeters = 25.0, exitMeters = 40.0, maxAccuracyMeters = 15.0;
  static const maxFixAge = Duration(seconds: 10), dwell = Duration(seconds: 3);
}

class GameSpot {
  const GameSpot({
    required this.id,
    required this.name,
    required this.point,
    this.gameId = 'free-kick',
    this.enabled = true,
    this.attackMeters,
    this.entryMeters = ProximitySettings.entryMeters,
    this.exitMeters = ProximitySettings.exitMeters,
  }) : assert(entryMeters > 0 && exitMeters > entryMeters);
  final String id, name, gameId;
  final CampusPoint point;
  final bool enabled;
  final double entryMeters, exitMeters;
  final double? attackMeters;
}

class PointState {
  const PointState({
    this.ownerTeamId,
    this.hp = 100,
    this.maxHp = 100,
    this.revision = 0,
  });
  factory PointState.fromJson(Map<String, dynamic> j) => PointState(
    ownerTeamId: j['owner_team_id'] as String?,
    hp: (j['hp'] as num).toDouble(),
    maxHp: j['max_hp'] as int,
    revision: j['revision'] as int,
  );
  final String? ownerTeamId;
  final double hp;
  final int maxHp, revision;
  double get healthPercent => hp / maxHp * 100;
  String get healthLabel => '${healthText(healthPercent)}%';
  String get owner => ownerTeamId == null
      ? 'Unclaimed'
      : GameTeam.fromId(ownerTeamId!).displayName;
  Map<String, dynamic> toJson() => {
    'owner_team_id': ownerTeamId,
    'hp': hp,
    'max_hp': maxHp,
    'revision': revision,
  };
}

/// Complete authoritative row plus its referenced rule set. No live fallback data.
class LiveGamePoint extends GameSpot {
  LiveGamePoint.fromJson(Map<String, dynamic> j)
    : description = j['description'] as String,
      imageUrl = j['image_url'] as String?,
      rules = AttackRules.fromJson(
        Map<String, dynamic>.from(j['rules'] as Map),
      ),
      state = PointState.fromJson(j),
      playVersion = j['play_version'] as int,
      super(
        id: j['id'] as String,
        name: j['name'] as String,
        point: CampusPoint(
          (j['longitude'] as num).toDouble(),
          (j['latitude'] as num).toDouble(),
        ),
        gameId: j['game_id'] as String,
        enabled: j['enabled'] as bool,
        attackMeters: (j['attack_meters'] as num).toDouble(),
        entryMeters: (j['entry_meters'] as num).toDouble(),
        exitMeters: (j['exit_meters'] as num).toDouble(),
      ) {
    if (name.isEmpty ||
        !point.latitude.isFinite ||
        point.latitude.abs() > 90 ||
        !point.longitude.isFinite ||
        point.longitude.abs() > 180 ||
        entryMeters <= 0 ||
        exitMeters <= entryMeters ||
        attackMeters! <= 0 ||
        state.maxHp <= 0 ||
        state.hp <= 0 ||
        state.hp > state.maxHp) {
      throw const FormatException('Invalid live point.');
    }
  }
  final String description;
  final String? imageUrl;
  final AttackRules rules;
  final PointState state;
  final int playVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'image_url': imageUrl,
    'latitude': point.latitude,
    'longitude': point.longitude,
    'game_id': gameId,
    'enabled': enabled,
    'attack_meters': attackMeters,
    'entry_meters': entryMeters,
    'exit_meters': exitMeters,
    'play_version': playVersion,
    'rules': rules.toJson(),
    ...state.toJson(),
  };
  LiveGamePoint withState(PointState next) =>
      LiveGamePoint.fromJson({...toJson(), ...next.toJson()});
}
