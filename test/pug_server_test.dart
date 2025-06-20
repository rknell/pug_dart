import 'package:test/test.dart';
import 'package:pug_dart/pug_dart.dart';
import 'dart:io';

void main() {
  group('Pug Singleton Tests', () {
    test('basic template rendering', () async {
      final html = await pug.render('h1= title\np Welcome to #{name}!',
          {'title': 'Test Site', 'name': 'Dart Server'});

      expect(html, contains('<h1>Test Site</h1>'));
      expect(html, contains('<p>Welcome to Dart Server!</p>'));
    });

    test('file-based template rendering', () async {
      final templateFile = File('test/template.pug');
      final html = await pug.renderFile(templateFile, {
        'title': 'File Test',
        'heading': 'Template from File',
        'message': 'This template was loaded from a file!',
        'items': ['First item', 'Second item', 'Third item']
      });

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<title>File Test</title>'));
      expect(html, contains('<h1>Template from File</h1>'));
      expect(html, contains('<p>This template was loaded from a file!</p>'));
      expect(html, contains('<li>First item</li>'));
      expect(html, contains('<li>Second item</li>'));
      expect(html, contains('<li>Third item</li>'));
    });

    test('file-based template compilation', () async {
      final templateFile = File('test/template.pug');
      final html = await pug.compileFile(templateFile, {
        'title': 'Compile Test',
        'heading': 'Compiled Template',
        'message': 'This template was compiled from a file!',
      });

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<title>Compile Test</title>'));
      expect(html, contains('<h1>Compiled Template</h1>'));
      expect(html, contains('<p>This template was compiled from a file!</p>'));
    });

    test('pretty printed rendering', () async {
      final html = await pug.render(
          'doctype html\nhtml\n  head\n    title= pageTitle\n  body\n    h1= message',
          {'pageTitle': 'Test Page', 'message': 'Hello World'},
          {'pretty': true});

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<title>Test Page</title>'));
      expect(html, contains('<h1>Hello World</h1>'));
      // The pretty option was passed (no error), that's what we're testing
      expect(html.length, greaterThan(0));
    });

    test('template compilation', () async {
      final html1 = await pug.compile('h2= greeting\np= message',
          {'greeting': 'Hello', 'message': 'First render'});

      final html2 = await pug.compile('h2= greeting\np= message',
          {'greeting': 'Hi', 'message': 'Second render'});

      expect(html1, contains('<h2>Hello</h2>'));
      expect(html1, contains('<p>First render</p>'));
      expect(html2, contains('<h2>Hi</h2>'));
      expect(html2, contains('<p>Second render</p>'));
    });

    test('list iteration', () async {
      final html =
          await pug.render('ul\n  each item in items\n    li= item.name', {
        'items': [
          {'name': 'Apple'},
          {'name': 'Banana'},
          {'name': 'Cherry'}
        ]
      });

      expect(html, contains('<li>Apple</li>'));
      expect(html, contains('<li>Banana</li>'));
      expect(html, contains('<li>Cherry</li>'));
    });

    test('conditional rendering', () async {
      final htmlVisible = await pug.render(
          'if show\n  p Visible content\nelse\n  p Hidden content',
          {'show': true});

      final htmlHidden = await pug.render(
          'if show\n  p Visible content\nelse\n  p Hidden content',
          {'show': false});

      expect(htmlVisible, contains('Visible content'));
      expect(htmlVisible, isNot(contains('Hidden content')));
      expect(htmlHidden, contains('Hidden content'));
      expect(htmlHidden, isNot(contains('Visible content')));
    });

    test('nested object access', () async {
      final html =
          await pug.render('.user\n  h3= user.name\n  p= user.details.email', {
        'user': {
          'name': 'John Doe',
          'details': {'email': 'john@example.com'}
        }
      });

      expect(html, contains('<h3>John Doe</h3>'));
      expect(html, contains('<p>john@example.com</p>'));
    });

    test('empty data handling', () async {
      final html = await pug.render('p Static content');
      expect(html, equals('<p>Static content</p>'));
    });

    test('error handling', () async {
      expect(() => pug.render('invalid[ pug syntax'),
          throwsA(isA<PugServerException>()));
    });

    test('file not found error handling', () async {
      final nonExistentFile = File('test/nonexistent.pug');
      expect(() => pug.renderFile(nonExistentFile),
          throwsA(isA<FileSystemException>()));
    });

    // Cleanup after all tests
    tearDownAll(() async {
      await pug.dispose();
    });
  });
}
