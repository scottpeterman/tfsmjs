# TextFSM JavaScript [tfsm.js]

A JavaScript port of the Python TextFSM library for parsing semi-structured text through template files.

*This project is a JavaScript implementation of [TextFSM](https://github.com/google/textfsm) originally developed by Google. Test data and templates are from [NTC-Templates](https://github.com/networktocode/ntc-templates).*

## Overview

TextFSM JS is a fully compatible JavaScript implementation of the original Python [TextFSM](https://github.com/google/textfsm) library. It enables parsing of semi-structured text (like CLI output from network devices) into structured data using simple templates.

This implementation achieves over 92% compatibility with the original Python library, with identical results for the vast majority of templates and even better performance in many cases.

## Features

- Complete TextFSM engine implementation in JavaScript
- Compatible with existing TextFSM templates
- Support for both Node.js and browser environments
- Comprehensive API for template parsing and text processing
- Excellent performance (often faster than the Python original)

## Project Structure

```
tfsmjs/
├── tfsm-node.js            # Node.js implementation
├── tfsm.js                 # Browser implementation
├── templates/              # TextFSM template files
│   └── cisco_ios_*.textfsm # Cisco IOS templates
├── tests/                  # Test files
│   └── cisco_ios/          # Test data for Cisco IOS
│       └── */              # Test directories by command
│           ├── *.raw       # Raw device output
│           └── *.yml       # Expected parse results
├── batch-textfsm-tester.js # Batch testing script
└── python-textfsm-tester.py # Python comparison tester
```# TextFSM JavaScript

A JavaScript port of the [Python TextFSM](https://github.com/google/textfsm) library for parsing semi-structured text through template files.

*This project is a JavaScript implementation of [TextFSM](https://github.com/google/textfsm) originally developed by Google. Test data and templates are from [NTC-Templates](https://github.com/networktocode/ntc-templates).*

**Repository**: [https://github.com/scottpeterman/tfsmjs](https://github.com/scottpeterman/tfsmjs)

## Overview

TextFSM JS is a fully compatible JavaScript implementation of the original Python [TextFSM](https://github.com/google/textfsm) library. It enables parsing of semi-structured text (like CLI output from network devices) into structured data using simple templates.

This implementation achieves over 92% compatibility with the original Python library, with identical results for the vast majority of templates and even better performance in many cases.

## Features

- Complete TextFSM engine implementation in JavaScript
- Compatible with existing TextFSM templates
- Support for both Node.js and browser environments
- Comprehensive API for template parsing and text processing
- Excellent performance (often faster than the Python original)

## Installation

Since this package is not yet available on npm, you can install it directly from GitHub:

```bash
# Clone the repository
git clone https://github.com/scottpeterman/tfsmjs.git

# Navigate to the project directory
cd tfsmjs

# If you're using this in another project, you can link it or copy the necessary files
```

### Using in Your Project

You can require the library directly from your local clone:

```javascript
// Node.js
const { TextFSM } = require('./path/to/tfsmjs/tfsm-node.js');

// Or import for browser/ES modules
import { TextFSM } from './path/to/tfsmjs/tfsm.js';
```

## Usage Examples

### Basic Usage (Node.js)

```javascript
const fs = require('fs');
const path = require('path');
const { TextFSM } = require('textfsm-js');

// Load a template
const templatePath = path.join(__dirname, 'templates', 'cisco_ios_show_ip_interface_brief.textfsm');
const templateContent = fs.readFileSync(templatePath, 'utf8');

// Sample CLI output
const sampleInput = `
Interface                  IP-Address      OK? Method Status                Protocol
FastEthernet0/0            192.168.1.1     YES NVRAM  up                    up
GigabitEthernet0/1         unassigned      YES NVRAM  administratively down down
`;

// Create a TextFSM parser with the template
const fsm = new TextFSM(templateContent);

// Parse the input
const result = fsm.parseTextToDicts(sampleInput);

// Display the results
console.log(JSON.stringify(result, null, 2));
```

### Browser Usage

```javascript
import { TextFSM } from 'textfsm-js';

// Assume templateContent is loaded via fetch or included in your bundle
const fsm = new TextFSM(templateContent);
const result = fsm.parseTextToDicts(deviceOutput);

// Use the structured data
console.log(result);
```

## API Reference

### Main Classes

#### TextFSM

The primary class for template parsing and text processing.

```javascript
// Create a new TextFSM instance
const fsm = new TextFSM(templateContent);

// Methods
const result = fsm.parseText(text);         // Parse text and return array of arrays
const dictResult = fsm.parseTextToDicts(text); // Parse text and return array of objects
```

#### TextFSMRule

Represents a rule in a TextFSM template.

#### TextFSMValue

Represents a value definition in a TextFSM template.

#### TextFSMOptions

Handles value options (Required, Filldown, Fillup, Key, List).

### Error Classes

- `TextFSMError`: Base error class
- `TextFSMTemplateError`: Template syntax or validation errors

## Template Format

TextFSM JS maintains compatibility with the original TextFSM template format:

```
Value INTERFACE (\S+)
Value IP_ADDR (\S+)
Value STATUS (up|down|administratively down)
Value PROTO (up|down)

Start
  ^${INTERFACE}\s+${IP_ADDR}\s+\w+\s+\w+\s+${STATUS}\s+${PROTO} -> Record
```

## Performance

TextFSM JS achieves excellent performance, typically processing templates in 1-10ms:

```
Average parse time: 1.19ms

Fastest templates:
  show_ip_vrf_interfaces: 0.25ms (0 records)
  show_module_online_diag: 0.29ms (6 records)
  show_power_supplies: 0.29ms (1 records)
  
Slowest templates:
  show_ip_interface: 9.23ms (83 records)
  show_processes_cpu: 7.62ms (316 records)
  show_crypto_ipsec_sa_detail: 4.92ms (4 records)
```

In many cases, the JavaScript implementation is faster than the original Python version.

## Compatibility

The library achieves 92.1% compatibility with the original Python TextFSM:

- 117 of 127 templates work perfectly out of the box
- 10 templates require minor adjustments

Common compatibility issues:

1. **Regular Expression Syntax**: JavaScript regex engine has some differences from Python's, particularly with lookbehind assertions.

2. **Option Combinations**: The handling of certain option combinations (like Required + Filldown) may require adjustment.

## Testing

The project includes comprehensive test tools to validate template compatibility:

### JavaScript Test Suite

```bash
node batch-textfsm-tester.js
```

This runs all templates through the JavaScript implementation and reports success rates, timing, and errors.

### Python Comparison Test

```bash
python python-textfsm-tester.py
```

This runs the same templates through the original Python implementation for direct comparison.

## Browser Support

The library is designed to work in modern browsers with full support for ES6 features. No dependencies are required.

## Implementation Notes

Key aspects of the implementation:

1. **State Machine**: The core text parsing engine follows the same state machine approach as the original.

2. **Regular Expressions**: JavaScript regex patterns are adapted from Python's syntax.

3. **Value Processing**: Options like Filldown, Required, and Key are implemented with the same semantics.

4. **Error Handling**: Comprehensive error reporting for template validation and parsing issues.

## License

Apache License 2.0

This project is licensed under the Apache License 2.0, the same license as the original TextFSM project.

## Credits and Acknowledgements

This project would not be possible without:

- **TextFSM**: The original [TextFSM](https://github.com/google/textfsm) library developed by Google. This JavaScript implementation is a port of their work and maintains compatibility with their template format.

- **NTC-Templates**: The [NTC-Templates](https://github.com/networktocode/ntc-templates) project by Network to Code provides the extensive collection of templates and test data used to validate this implementation. Their comprehensive templates are essential for testing compatibility.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.