import 'dart:convert';
import 'dart:io';
import 'package:campus_app/map/campus_style.dart';

/// Produces the exact runtime style for offline spec validation (no token).
void main(List<String> args) {
  final file = File(args.isEmpty ? 'tmp/campus/style.json' : args.first);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode(
      CampusStyle.build(
        File('assets/campus/boundary.geojson').readAsStringSync(),
        File('assets/campus/features.geojson').readAsStringSync(),
      ),
    ),
  );
  stdout.writeln(file.path);
}
