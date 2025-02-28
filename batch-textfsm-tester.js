// batch-textfsm-tester.js
const fs = require('fs');
const path = require('path');
const { TextFSM } = require('./tfsm-node.js');

// Configuration
const TEMPLATE_DIR = path.join(__dirname, 'templates');
const TEST_DIR = path.join(__dirname, 'tests');
const VENDOR = 'cisco_ios';
const TEMPLATE_PREFIX = 'cisco_ios';
const MAX_PARALLEL_TESTS = 1; // Process sequentially to avoid overwhelming the system

// Stats collection
const stats = {
  total: 0,
  success: 0,
  failed: 0,
  skipped: 0,
  times: [],
  errors: []
};

// Find all template files
function findTemplates() {
  try {
    const files = fs.readdirSync(TEMPLATE_DIR);
    const templateFiles = files.filter(file =>
      file.startsWith(TEMPLATE_PREFIX) && file.endsWith('.textfsm')
    );

    console.log(`Found ${templateFiles.length} Cisco IOS templates`);
    return templateFiles;
  } catch (error) {
    console.error(`Error finding templates: ${error.message}`);
    return [];
  }
}

// Find raw file for a command
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
      // Directory exists but can't read it or no .raw files
    }
  }

  // If the directory doesn't exist or has no .raw files, search more broadly
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
      try {
        const files = fs.readdirSync(dirPath).filter(file => file.endsWith('.raw'));

        if (files.length > 0) {
          return path.join(dirPath, files[0]);
        }
      } catch (error) {
        // Continue to next directory
      }
    }
  } catch (error) {
    // Failed to search
  }

  return null;
}

// Process a single template
async function processTemplate(templateFile) {
  stats.total++;
  const templatePath = path.join(TEMPLATE_DIR, templateFile);
  const commandName = path.basename(templateFile, '.textfsm').replace(/^cisco_ios_/, '');

  console.log(`\nTesting template: ${templateFile}`);

  try {
    // Find the raw file
    const rawFile = findRawFile(commandName);
    if (!rawFile) {
      console.log(`[SKIP] ${commandName}: No matching raw file found`);
      stats.skipped++;
      return;
    }

    // Load template and raw data
    const templateContent = fs.readFileSync(templatePath, 'utf8');
    const rawContent = fs.readFileSync(rawFile, 'utf8');

    // Use a timeout to prevent hanging
    let result;
    const startTime = process.hrtime();

    try {
      // Process with timeout protection
      await Promise.race([
        new Promise((resolve, reject) => {
          try {
            const fsm = new TextFSM(templateContent);
            result = fsm.parseTextToDicts(rawContent);
            resolve();
          } catch (error) {
            reject(error);
          }
        }),
        new Promise((_, reject) => {
          setTimeout(() => {
            reject(new Error('Parsing timed out after 10 seconds'));
          }, 10000);
        })
      ]);

      // Calculate execution time
      const [seconds, nanoseconds] = process.hrtime(startTime);
      const executionTimeMs = (seconds * 1000) + (nanoseconds / 1000000);

      // Record success
      console.log(`[PASS] ${commandName}: Parsed ${result.length} records in ${executionTimeMs.toFixed(2)}ms`);
      stats.success++;
      stats.times.push({
        template: templateFile,
        command: commandName,
        time: executionTimeMs,
        records: result.length
      });

    } catch (error) {
      // Record failure
      console.error(`[FAIL] ${commandName}: ${error.message}`);
      stats.failed++;
      stats.errors.push({
        template: templateFile,
        command: commandName,
        error: error.message
      });
    }

  } catch (error) {
    // File read error
    console.error(`[ERROR] ${commandName}: ${error.message}`);
    stats.failed++;
    stats.errors.push({
      template: templateFile,
      command: commandName,
      error: error.message
    });
  }
}

// Process templates in batches to avoid memory issues
async function processTemplates(templates) {
  // Process templates in batches
  for (let i = 0; i < templates.length; i += MAX_PARALLEL_TESTS) {
    const batch = templates.slice(i, i + MAX_PARALLEL_TESTS);
    await Promise.all(batch.map(template => processTemplate(template)));
  }
}

// Print summary statistics
function printSummary() {
  console.log('\n' + '='.repeat(50));
  console.log('TextFSM Testing Summary');
  console.log('='.repeat(50));

  console.log(`\nTotal templates tested: ${stats.total}`);
  console.log(`Successful: ${stats.success} (${((stats.success / stats.total) * 100).toFixed(1)}%)`);
  console.log(`Failed: ${stats.failed} (${((stats.failed / stats.total) * 100).toFixed(1)}%)`);
  console.log(`Skipped: ${stats.skipped} (${((stats.skipped / stats.total) * 100).toFixed(1)}%)`);

  if (stats.times.length > 0) {
    // Calculate average time
    const totalTime = stats.times.reduce((sum, item) => sum + item.time, 0);
    const avgTime = totalTime / stats.times.length;

    console.log(`\nAverage parse time: ${avgTime.toFixed(2)}ms`);

    // Sort by time and get fastest/slowest
    stats.times.sort((a, b) => a.time - b.time);

    console.log('\nFastest templates:');
    stats.times.slice(0, 5).forEach(item => {
      console.log(`  ${item.command}: ${item.time.toFixed(2)}ms (${item.records} records)`);
    });

    console.log('\nSlowest templates:');
    stats.times.slice(-5).reverse().forEach(item => {
      console.log(`  ${item.command}: ${item.time.toFixed(2)}ms (${item.records} records)`);
    });
  }

  if (stats.errors.length > 0) {
    console.log('\nFailed templates:');
    stats.errors.forEach(item => {
      console.log(`  ${item.command}: ${item.error}`);
    });
  }

  // Print overall assessment
  console.log('\n' + '='.repeat(50));
  const successRate = (stats.success / stats.total) * 100;
  if (successRate === 100) {
    console.log('✅ All templates passed!');
  } else if (successRate >= 90) {
    console.log('🟢 Most templates are working correctly.');
  } else if (successRate >= 75) {
    console.log('🟡 The majority of templates are working, but some need attention.');
  } else {
    console.log('🔴 Several templates need attention.');
  }
  console.log('='.repeat(50));
}

// Main execution
async function main() {
  console.log('=== TextFSM Batch Testing ===');

  // Find templates
  const templates = findTemplates();
  if (templates.length === 0) {
    console.error('No templates found. Exiting.');
    process.exit(1);
  }

  // Process templates
  await processTemplates(templates);

  // Print summary
  printSummary();
}

// Handle uncaught exceptions to prevent crashes
process.on('uncaughtException', (error) => {
  console.error('Uncaught exception:', error.message);
  console.error('Continuing with next template...');
});

// Start the program
main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});