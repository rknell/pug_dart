import 'package:pug_dart/pug_dart.dart' as pug;

Future<void> main() async {
  final html = await pug.render('p Hello #{name}', {'name': 'Dart'});
  print(html);
}
