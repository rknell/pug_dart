const pug = require('pug');
const fs = require('fs');

// Read input from stdin
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  input += chunk;
});

process.stdin.on('end', () => {
  try {
    const request = JSON.parse(input);
    let result;
    
    switch (request.action) {
      case 'render':
        result = pug.render(request.template, request.data || {}, request.options || {});
        break;
      case 'renderFile':
        result = pug.renderFile(request.filename, request.data || {}, request.options || {});
        break;
      case 'compile':
        const compiled = pug.compile(request.template, request.options || {});
        result = compiled(request.data || {});
        break;
      case 'compileFile':
        const compiledFile = pug.compileFile(request.filename, request.options || {});
        result = compiledFile(request.data || {});
        break;
      case 'ping':
        result = 'pong';
        break;
      default:
        throw new Error('Unknown action: ' + request.action);
    }
    
    console.log(JSON.stringify({ success: true, result: result }));
  } catch (error) {
    console.log(JSON.stringify({ 
      success: false, 
      error: error.message,
      errorType: error.code || 'unknown'
    }));
  }
}); 