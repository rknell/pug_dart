// This example is deprecated since setup is now automatic.
// Use example/main.dart or example/test.dart instead.

import 'package:pug_dart/pug_dart.dart';

void main() async {
  print('Setup is now automatic! Just use pug.render() directly.');

  final html = await pug.render('h1 Automatic Setup Example');
  print('Rendered HTML: $html');

  await pug.dispose();
}
