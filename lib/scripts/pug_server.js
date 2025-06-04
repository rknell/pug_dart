const pug = require('pug');
const net = require('net');
const fs = require('fs');

// Socket path will be passed as the first command line argument
const socketPath = process.argv[2];

if (!socketPath) {
  console.error('Socket path is required as first argument');
  process.exit(1);
}

// Clean up socket file if it exists
if (fs.existsSync(socketPath)) {
  fs.unlinkSync(socketPath);
}

const server = net.createServer((socket) => {
  let buffer = '';
  
  socket.on('data', (data) => {
    buffer += data.toString();
    
    // Check if we have a complete message (ends with newline)
    const lines = buffer.split('\n');
    if (lines.length > 1) {
      // Process all complete lines except the last (incomplete) one
      for (let i = 0; i < lines.length - 1; i++) {
        const line = lines[i].trim();
        if (line) {
          processRequest(socket, line);
        }
      }
      // Keep the incomplete line in buffer
      buffer = lines[lines.length - 1];
    }
  });
  
  socket.on('error', (err) => {
    console.error('Socket error:', err);
  });
});

function processRequest(socket, requestStr) {
  let request;
  try {
    request = JSON.parse(requestStr);
  } catch (parseError) {
    // JSON parsing failed - send error without request ID
    const response = JSON.stringify({ 
      success: false, 
      error: 'Invalid JSON: ' + parseError.message 
    }) + '\n';
    socket.write(response);
    return;
  }

  try {
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
    
    const response = JSON.stringify({ 
      id: request.id, 
      success: true, 
      result: result 
    }) + '\n';
    socket.write(response);
  } catch (error) {
    const response = JSON.stringify({ 
      id: request.id, 
      success: false, 
      error: error.message,
      errorType: error.code || 'unknown'
    }) + '\n';
    socket.write(response);
  }
}

server.listen(socketPath, () => {
  console.log('ready');
});

server.on('error', (err) => {
  console.error('Server error:', err);
  process.exit(1);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  server.close(() => {
    if (fs.existsSync(socketPath)) {
      fs.unlinkSync(socketPath);
    }
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  server.close(() => {
    if (fs.existsSync(socketPath)) {
      fs.unlinkSync(socketPath);
    }
    process.exit(0);
  });
}); 