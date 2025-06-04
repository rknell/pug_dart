import 'package:pug_dart/pug_dart.dart';

void main() async {
  print('=== Pug Server Setup Example ===\n');

  // Check if Pug is available
  print('1. Checking if Pug.js is available...');
  final isAvailable = await PugServer.isAvailable();

  if (isAvailable) {
    print('✅ Pug.js is already available!\n');
  } else {
    print('❌ Pug.js is not available. Setting up...\n');

    // Setup Pug with verbose output
    print('2. Running setup...');
    final setupSuccess = await PugServer.setup(verbose: true);

    if (setupSuccess) {
      print('\n✅ Setup completed successfully!\n');
    } else {
      print('\n❌ Setup failed. Please install Node.js and npm manually.\n');
      return;
    }
  }

  // Test basic functionality
  print('3. Testing basic functionality:');
  try {
    final html = await PugServer.render(
      'h1 Setup Test\np Pug.js is working correctly!',
    );
    print('Output: $html\n');

    print('✅ Pug Dart is ready to use!');
    print('\nYou can now use PugServer.render(), PugServer.renderFile(),');
    print(
        'PugServer.compile(), and PugServer.compileFile() in your applications.');
  } catch (e) {
    print('❌ Test failed: $e');
    print('Please check your Node.js and npm installation.');
  }
}
