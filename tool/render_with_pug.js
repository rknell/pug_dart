const fs = require('fs');
const path = require('path');
const pug = require('pug');

const [file, localsFile, optionsFile] = process.argv.slice(2);
const locals = localsFile && fs.existsSync(localsFile)
  ? JSON.parse(fs.readFileSync(localsFile, 'utf8'))
  : {};
const fixtureOptions = optionsFile && fs.existsSync(optionsFile)
  ? JSON.parse(fs.readFileSync(optionsFile, 'utf8'))
  : {};

const options = {
  filename: path.resolve(file),
  basedir: fixtureOptions.basedir ? path.resolve(fixtureOptions.basedir) : undefined,
  pretty: fixtureOptions.pretty || false,
  doctype: fixtureOptions.doctype,
};

process.stdout.write(pug.renderFile(path.resolve(file), { ...locals, ...options }));
