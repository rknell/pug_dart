import 'package:pug_dart/pug_dart.dart';
import 'dart:io';

void main() async {
  print('=== Pug Server Examples ===\n');

  // Example 1: Basic template rendering
  print('1. Basic Template Rendering:');
  try {
    final html1 = await pug.render('h1= title\np Welcome to #{name}!',
        {'title': 'My Server', 'name': 'Dart Backend'});
    print('Output: $html1\n');
  } catch (e) {
    print('Error in basic rendering: $e\n');
  }

  // Example 2: Pretty printed output
  print('2. Pretty Printed Template:');
  try {
    final html2 = await pug.render(
        'doctype html\nhtml\n  head\n    title= pageTitle\n  body\n    h1= message\n    p This is a server-side rendered page.',
        {'pageTitle': 'Server Page', 'message': 'Hello from Dart Server!'},
        {'pretty': true});
    print('Output: $html2\n');
  } catch (e) {
    print('Error in pretty printing: $e\n');
  }

  // Example 3: Template compilation
  print('3. Template Compilation:');
  try {
    final users = [
      {'name': 'Alice', 'email': 'alice@example.com', 'role': 'Admin'},
      {'name': 'Bob', 'email': 'bob@example.com', 'role': 'User'},
    ];

    for (final user in users) {
      final html = await pug.compile(
          '.user-card\n  h2= user.name\n  p Email: #{user.email}\n  p Role: #{user.role}',
          {'user': user});
      print('User ${user['name']}: $html');
    }
    print('');
  } catch (e) {
    print('Error in template compilation: $e\n');
  }

  // Example 4: Lists and iteration
  print('4. Lists and Iteration:');
  try {
    final html4 = await pug.render(
        'h3 Server-side Shopping List\nul\n  each item in items\n    li #{item.name} - \$#{item.price}',
        {
          'items': [
            {'name': 'Server CPU', 'price': 299.99},
            {'name': 'RAM Module', 'price': 149.99},
            {'name': 'SSD Drive', 'price': 89.99},
          ]
        },
        {
          'pretty': true
        });
    print('Output: $html4\n');
  } catch (e) {
    print('Error in list iteration: $e\n');
  }

  // Example 5: File-based template rendering
  print('5. File-based Template Rendering:');
  try {
    final templateFile = File('test/template.pug');
    if (await templateFile.exists()) {
      final html5 = await pug.renderFile(templateFile, {
        'title': 'File-based Example',
        'heading': 'Template from File',
        'message':
            'This demonstrates file-based rendering using dart:io File objects!',
        'items': ['Feature 1', 'Feature 2', 'Feature 3']
      });
      print('Output: $html5\n');
    } else {
      print('Template file not found (test/template.pug)\n');
    }
  } catch (e) {
    print('Error in file rendering: $e\n');
  }

  print('=== Server Examples completed ===');

  // Clean up
  await pug.dispose();
}
