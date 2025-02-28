// simple-textfsm-tester.js
const fs = require('fs');
const path = require('path');
const { TextFSM } = require('./tfsm-node.js');

// Configuration
const TEMPLATE_DIR = path.join(__dirname, 'templates');
const TEST_DIR = path.join(__dirname, 'tests');
const VENDOR = 'cisco_ios';

// Get specific template from command line arg
const templateFile = process.argv[2];
if (!templateFile) {
  console.error('Usage: node simple-textfsm-tester.js <template-filename>');
  console.error('Example: node simple-textfsm-tester.js cisco_ios_show_arp.textfsm');
  process.exit(1);
}

console.log(`=== Testing TextFSM Template: ${templateFile} ===\n`);

// Verify template exists
const templatePath = path.join(TEMPLATE_DIR, templateFile);
if (!fs.existsSync(templatePath)) {
  console.error(`Error: Template file not found: ${templatePath}`);
  process.exit(1);
}

// Extract command name from template filename
const commandName = path.basename(templateFile, '.textfsm').replace(/^cisco_ios_/, '');
console.log(`Command name: ${commandName}`);

// Find the raw file
function findRawFile(commandName) {
  // Check in the most likely location first
  const dirPath = path.join(TEST_DIR, VENDOR, commandName);
  if (fs.existsSync(dirPath)) {
    try {
      // Get all files with .raw extension in the directory
      const files = fs.readdirSync(dirPath).filter(file => file.endsWith('.raw'));
      if (files.length > 0) {
        return path.join(dirPath, files[0]);
      }
    } catch (error) {
      console.error(`Error reading directory: ${error.message}`);
    }
  }

  // If the directory doesn't exist or has no .raw files, search more broadly
  console.log('Directory path not found, searching for similar paths...');

  try {
    const vendorDir = path.join(TEST_DIR, VENDOR);
    const directories = fs.readdirSync(vendorDir, { withFileTypes: true })
      .filter(dirent => dirent.isDirectory())
      .map(dirent => dirent.name);

    // Look for a directory that might match
    const possibleDirs = directories.filter(dir =>
      dir.includes(commandName) || commandName.includes(dir));

    for (const dir of possibleDirs) {
      const dirPath = path.join(vendorDir, dir);
      const files = fs.readdirSync(dirPath).filter(file => file.endsWith('.raw'));

      if (files.length > 0) {
        return path.join(dirPath, files[0]);
      }
    }
  } catch (error) {
    console.error(`Error searching for raw file: ${error.message}`);
  }

  return null;
}

const rawFile = findRawFile(commandName);
if (!rawFile) {
  console.error(`Error: Could not find raw file for command: ${commandName}`);
  process.exit(1);
}

console.log(`Found raw file: ${rawFile}`);

// Test the template with the raw file
try {
  // Read the template and raw data
  console.log('Reading template and raw data...');
  const templateContent = fs.readFileSync(templatePath, 'utf8');
  const rawContent = fs.readFileSync(rawFile, 'utf8');

  // Measure performance
  console.log('Parsing with TextFSM...');
  const startTime = process.hrtime();

  // Create parser and parse
  const fsm = new TextFSM(templateContent);
  const result = fsm.parseTextToDicts(rawContent);

  // Calculate execution time
  const [seconds, nanoseconds] = process.hrtime(startTime);
  const executionTimeMs = (seconds * 1000) + (nanoseconds / 1000000);

  // Output results
  console.log('\n=== Parsing Results ===');
  console.log(`Status: SUCCESS`);
  console.log(`Execution time: ${executionTimeMs.toFixed(2)}ms`);
  console.log(`Records parsed: ${result.length}`);

  if (result.length > 0) {
    console.log('\nSample record:');
    console.log(JSON.stringify(result[0], null, 2));

    console.log('\nRecord fields:');
    const fields = Object.keys(result[0]);
    fields.forEach(field => {
      console.log(`- ${field}`);
    });
  }

  console.log('\n=== TextFSM Template Summary ===');
  console.log(`Template name: ${templateFile}`);
  console.log(`Values: ${fsm.values.length}`);
  const valueNames = fsm.values.map(v => v.name);
  console.log(`Value names: ${valueNames.join(', ')}`);

} catch (error) {
  console.error('\n=== Parsing Error ===');
  console.error(`Status: FAILED`);
  console.error(`Error: ${error.message}`);
  console.error(`Stack: ${error.stack}`);
}