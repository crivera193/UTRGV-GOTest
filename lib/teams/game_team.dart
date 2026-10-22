import 'package:flutter/material.dart';

/// Stable identifiers; display copy can change without changing membership.
enum GameTeam {
  healthScience(
    'health_science',
    'Health and Science',
    'Blue',
    Color(0xff77bfff),
    'Stay curious. Explore life, wellbeing and the world around you.',
  ),
  mathEngineering(
    'math_engineering',
    'Math and Engineering',
    'Red',
    Color(0xffff9292),
    'Think boldly. Find patterns, solve puzzles and build new possibilities.',
  ),
  artStuff(
    'art_stuff',
    'Art and Stuff',
    'Yellow',
    Color(0xffffdf7b),
    'Make your mark. Bring imagination, expression and a fresh perspective.',
  );

  const GameTeam(
    this.id,
    this.displayName,
    this.colorName,
    this.color,
    this.description,
  );
  final String id, displayName, colorName, description;
  final Color color;

  static GameTeam fromId(String id) => values.firstWhere(
    (team) => team.id == id,
    orElse: () => throw const FormatException('Unrecognized account team.'),
  );
}
