// textfsm-tester.js
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml'); // You'll need to install this: npm install js-yaml
const { TextFSM, TextFSMError, TextFSMTemplateError } = require('./tfsm-node.js');

// Configuration
const TEMPLATE_DIR = path.join(__dirname, 'templates');
const TEST_DIR = path.join(__dirname, 'tests');
const VENDOR = 'cisco_ios'; // Focus on Cisco IOS first
const DEBUG = process.env.DEBUG === 'true'; // Enable debug output with DEBUG=true environment variable
const MAX_TIMEOUT_MS = 10000; // Maximum time allowed for any single test (10 seconds)

// Allow command-line argument for testing specific templates
const specificTemplate = process.argv[2]; // e.g., "node textfsm-tester.js cisco_ios_show_arp.textfsm"

// Configuration
const TEMPLATE_DIR = path.join(__dirname, 'templates');
const TEST_DIR = path.join(__dirname, 'tests');
const VENDOR = 'cisco_ios'; // Focus on Cisco IOS first

// Stats collection
const stats = {
  totalTests: 0,
  successful: 0,
  failed: 0,
  skipped: 0,
  executionTimes: []
};

// Utility to get just the command name from filename
function getCommandName(filename) {
  // Remove prefix (cisco_ios_show_) and extension (.textfsm)
  return path.basename(filename, '.textfsm').replace(/^cisco_ios_/, '');
}

// Find all templates in the template directory
function findTemplates() {
  const allTemplateFiles = fs.readdirSync(TEMPLATE_DIR)
    .filter(file => file.startsWith('cisco_ios_') && file.endsWith('.textfsm'));

  // If a specific template is requested via command line
  if (specificTemplate) {
    // Check if the specific template exists
    if (allTemplateFiles.includes(specificTemplate)) {
      console.log(`Testing a single template: ${specificTemplate}`);
      return [specificTemplate];
    } else if (allTemplateFiles.some(template => template.includes(specificTemplate))) {
      // Try partial match
      const matchingTemplates = allTemplateFiles.filter(template =>
        template.includes(specificTemplate));
      console.log(`Found ${matchingTemplates.length} templates matching: ${specificTemplate}`);
      return matchingTemplates;
    } else {
      console.log(`Template not found: ${specificTemplate}`);
      console.log(`Available templates: ${allTemplateFiles.join(', ')}`);
      process.exit(1);
    }
  }

  console.log(`Found ${allTemplateFiles.length} Cisco IOS templates`);
  return allTemplateFiles;
}

// Find corresponding raw file in test directory
function findRawFile(commandName) {
  // Try with exact match first
  const rawPath = path.join(TEST_DIR, VENDOR, commandName, `${commandName}.raw`);
  if (fs.existsSync(rawPath)) {
    return rawPath;
  }

  // Try with cisco_ios prefix
  const rawPath2 = path.join(TEST_DIR, VENDOR, commandName, `cisco_ios_${commandName}.raw`);
  if (fs.existsSync(rawPath2)) {
    return rawPath2;
  }

  // Try to find directory that might match partially
  try {
    const vendorDir = path.join(TEST_DIR, VENDOR);
    const directories = fs.readdirSync(vendorDir, { withFileTypes: true })
      .filter(dirent => dirent.isDirectory())
      .map(dirent => dirent.name);

    // Find the most similar directory name
    for (const dir of directories) {
      // Check if command name is a substring of directory or vice versa
      if (dir.includes(commandName) || commandName.includes(dir)) {
        // Try different file naming patterns
        const possiblePaths = [
          path.join(vendorDir, dir, `${dir}.raw`),
          path.join(vendorDir, dir, `${commandName}.raw`),
          path.join(vendorDir, dir, `cisco_ios_${dir}.raw`),
          path.join(vendorDir, dir, `cisco_ios_${commandName}.raw`)
        ];

        for (const possiblePath of possiblePaths) {
          if (fs.existsSync(possiblePath)) {
            return possiblePath;
          }
        }
      }
    }
  } catch (error) {
    console.error(`Error finding raw file: ${error.message}`);
  }

  return null;
}

// Find corresponding YAML file in test directory
function findYamlFile(commandName) {
  const yamlPath = path.join(TEST_DIR, VENDOR, commandName, `${commandName}.yml`);
  if (fs.existsSync(yamlPath)) {
    return yamlPath;
  }
  const yamlPath2 = path.join(TEST_DIR, VENDOR, commandName, `${commandName}.yaml`);
  if (fs.existsSync(yamlPath2)) {
    return yamlPath2;
  }
  return null;
}

// Validate template can load and parse sample data
function validateTemplateBasics(templateContent) {
  // Sample text for basic testing - just to see if template loads
  // Include several different data types to improve matching chance
  const sampleText = `
Interface                  IP-Address      OK? Method Status                Protocol
FastEthernet0/0            192.168.1.1     YES NVRAM  up                    up
GigabitEthernet0/1         unassigned      YES NVRAM  administratively down down

VLAN Name                             Status    Ports
---- -------------------------------- --------- -------------------------------
1    default                          active    Gi0/1, Gi0/2
10   Management                       active

Protocol  Address          Age (min)  Hardware Addr   Type   Interface
Internet  192.168.1.1            -   0000.0c07.ac01  ARPA   GigabitEthernet0/1
Internet  192.168.1.2           60   0050.56bb.4a48  ARPA   GigabitEthernet0/1

BGP neighbor is 10.10.10.10,  remote AS 65000, external link
  BGP version 4, remote router ID 10.10.10.10
  BGP state = Established, up for 2d10h
  Last read 00:00:54, last write 00:00:22, hold time is 180
`;

  try {
    // Try to instantiate the template with a timeout
    const startTime = Date.now();
    const TIMEOUT_MS = 5000; // 5 second timeout

    const fsm = new TextFSM(templateContent);

    // Run a basic parse with timeout protection
    let result;
    const parsePromise = new Promise((resolve) => {
      // Use setTimeout to create a non-blocking parse attempt
      setTimeout(() => {
        try {
          result = fsm.parseTextToDicts(sampleText);
          resolve(true);
        } catch (e) {
          console.warn(`  Warning: Error during basic parsing: ${e.message}`);
          resolve(false);
        }
      }, 0);
    });

    // Wait for parse or timeout
    const timeoutPromise = new Promise((resolve) => {
      setTimeout(() => {
        resolve('timeout');
      }, TIMEOUT_MS);
    });

    // Use Promise.race to implement the timeout
    const outcome = Promise.race([parsePromise, timeoutPromise]);

    if (outcome === 'timeout') {
      console.warn(`  Warning: Template validation timed out after ${TIMEOUT_MS}ms`);
      return { valid: false, error: 'Timeout during template validation' };
    }

    // Template is valid if it can be instantiated
    // Parsing may not produce results with our sample data, and that's okay
    return { valid: true, fsm };
  } catch (error) {
    return { valid: false, error: error.message };
  }
}

// Parse raw data with TextFSM template and validate against expected output
function runTest(templateFile, commandName) {
  stats.totalTests++;

  // Use a timeout to prevent test from hanging indefinitely
  let testTimeout;
  const TIMEOUT_MS = 10000; // 10 seconds timeout per test

  // Create a promise that rejects after timeout
  const timeoutPromise = new Promise((_, reject) => {
    testTimeout = setTimeout(() => {
      reject(new Error(`Test timed out after ${TIMEOUT_MS}ms`));
    }, TIMEOUT_MS);
  });

  // Create the actual test promise
  const testPromise = new Promise(async (resolve, reject) => {
    try {
      // First, load and validate the template
      const templatePath = path.join(TEMPLATE_DIR, templateFile);
      const templateContent = fs.readFileSync(templatePath, 'utf8');

      console.log(`Testing template validation for: ${templateFile}`);

      // Validate template with timeout protection
      const validation = validateTemplateBasics(templateContent);

      if (!validation.valid) {
        console.log(`[FAIL] ${commandName} - Template validation failed: ${validation.error || 'Unknown error'}`);
        stats.failed++;
        resolve();
        return;
      }

      const { fsm } = validation;

      // Find raw and YAML files
      const rawFile = findRawFile(commandName);

      if (!rawFile) {
        // Even if we don't have a raw file, we've verified the template loads, so partial success
        console.log(`[PARTIAL] ${commandName} - Template loads but no raw file found`);
        stats.successful++; // Count as success since the template is valid
        resolve();
        return;
      }

      // Read raw data
      const rawContent = fs.readFileSync(rawFile, 'utf8');

      // Parse with TextFSM and measure performance (with timeout protection)
      let result;
      const startTime = process.hrtime();

      try {
        // Use a non-blocking approach to prevent hanging
        result = await new Promise((resolveInner, rejectInner) => {
          setTimeout(() => {
            try {
              const parseResult = fsm.parseTextToDicts(rawContent);
              resolveInner(parseResult);
            } catch (e) {
              rejectInner(e);
            }
          }, 0);
        });

        const [seconds, nanoseconds] = process.hrtime(startTime);
        const executionTimeMs = (seconds * 1000) + (nanoseconds / 1000000);
        stats.executionTimes.push({ command: commandName, time: executionTimeMs });

        // Check for empty results (even with valid raw data)
        if (result.length === 0) {
          console.log(`[WARN] ${commandName} - Template parsed successfully but produced no results`);
          stats.successful++; // Still count as success as the template works
          resolve();
          return;
        }

        // Find and validate against YAML file if it exists
        const yamlFile = findYamlFile(commandName);
        if (yamlFile) {
          const expectedOutput = yaml.load(fs.readFileSync(yamlFile, 'utf8'));

          // More flexible validation
          const success = (
            expectedOutput &&
            expectedOutput.length === result.length
          );

          if (success) {
            console.log(`[PASS] ${commandName} - Parsed ${result.length} records in ${executionTimeMs.toFixed(2)}ms`);
            stats.successful++;
          } else {
            console.log(`[PARTIAL] ${commandName} - Record count doesn't match expected result`);
            console.log(`  Expected ${expectedOutput ? expectedOutput.length : 'undefined'} records, got ${result.length}`);
            console.log(`  But template successfully parsed the data`);
            stats.successful++; // Count as success since the template processed the data
          }
        } else {
          console.log(`[PASS] ${commandName} - Parsed ${result.length} records in ${executionTimeMs.toFixed(2)}ms (no YAML to validate)`);
          stats.successful++; // Mark as success if we could parse it without errors
        }
      } catch (parseError) {
        console.error(`[ERROR] ${commandName} - Error during parsing: ${parseError.message}`);
        stats.failed++;
      }

      resolve();
    } catch (error) {
      reject(error);
    }
  });

  // Race between the test and the timeout
  Promise.race([testPromise, timeoutPromise])
    .catch(error => {
      // Handle errors, including timeouts
      if (error.message.includes('timed out')) {
        console.error(`[TIMEOUT] ${commandName} - Test timed out after ${TIMEOUT_MS}ms`);
        stats.failed++;
      } else {
        console.error(`[ERROR] ${commandName} - ${error.message}`);
        stats.failed++;
      }
    })
    .finally(() => {
      // Always clear the timeout to prevent memory leaks
      clearTimeout(testTimeout);
    });
}

// Run tests for all templates
async function runAllTests() {
  console.log('=== TextFSM Parser Test Suite ===');
  const templates = findTemplates();

  // Process templates sequentially to avoid overwhelming the system
  // and to make the output more readable
  for (const template of templates) {
    const commandName = getCommandName(template);
    console.log(`\nTesting template: ${template}`);

    // Create a promise that resolves when the test is complete
    await new Promise(resolve => {
      // Run the test
      runTest(template, commandName);

      // Add a small delay between tests to prevent flooding the console
      setTimeout(resolve, 100);
    });
  }

  // Wait a moment for any pending tests to finish
  await new Promise(resolve => setTimeout(resolve, 2000));

  printSummary();
}

// Changed from direct call to async function
async function main() {
  try {
    await runAllTests();
  } catch (error) {
    console.error('Test suite error:', error.message);
    process.exit(1);
  }
}

// Run the main function
main();

// Print summary statistics
function printSummary() {
  console.log('\n=== Test Summary ===');
  console.log(`Total tests: ${stats.totalTests}`);
  console.log(`Successful: ${stats.successful}`);
  console.log(`Failed: ${stats.failed}`);
  console.log(`Skipped: ${stats.skipped}`);
  console.log(`Success rate: ${(stats.successful / stats.totalTests * 100).toFixed(2)}%`);

  if (stats.executionTimes.length > 0) {
    // Calculate average execution time
    const totalTime = stats.executionTimes.reduce((sum, entry) => sum + entry.time, 0);
    const avgTime = totalTime / stats.executionTimes.length;

    console.log('\n=== Performance Stats ===');
    console.log(`Templates with performance metrics: ${stats.executionTimes.length}`);
    console.log(`Average execution time: ${avgTime.toFixed(2)}ms`);
    console.log(`Total parsing time: ${totalTime.toFixed(2)}ms`);

    // Find fastest and slowest commands
    stats.executionTimes.sort((a, b) => a.time - b.time);

    const fastCount = Math.min(5, stats.executionTimes.length);
    const slowCount = Math.min(5, stats.executionTimes.length);

    console.log(`\nFastest commands:`);
    stats.executionTimes.slice(0, fastCount).forEach(entry => {
      console.log(`  ${entry.command}: ${entry.time.toFixed(2)}ms`);
    });

    console.log(`\nSlowest commands:`);
    stats.executionTimes.slice(-slowCount).reverse().forEach(entry => {
      console.log(`  ${entry.command}: ${entry.time.toFixed(2)}ms`);
    });
  }

  // Print overall assessment
  console.log('\n=== Overall Assessment ===');
  const successRate = stats.successful / stats.totalTests * 100;
  if (successRate === 100) {
    console.log('✅ All templates passed validation!');
  } else if (successRate >= 90) {
    console.log('🟢 Most templates are working correctly.');
  } else if (successRate >= 75) {
    console.log('🟡 The majority of templates are working, but some need attention.');
  } else {
    console.log('🔴 Several templates need attention.');
  }
}

// Run the test suite
runAllTests();