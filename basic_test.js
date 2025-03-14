// test-node.js
const fs = require('fs');
const path = require('path');
const { TextFSM } = require('./tfsm-node.js');

// Path to a simple template and sample input
const templatePath = path.join(__dirname, 'templates', 'cisco_ios_show_capability_feature_routing.textfsm');
const sampleInput = `Displaying capability information for all available features:
L3VPN Inter-AS Hybrid: Enabled
L3VPN PE-CE Link Protection: Enabled
OSPF nssa-only: Enabled
OSPF Connected prefix suppression: Enabled
OSPF support of RFC3101: Enabled
OSPF prefix priority: Enabled
OSPFv3 IPsec auth/encr: Enabled
OSPFv3 BFD: Enabled
OSPFv3 Graceful Restart: Enabled
OSPFv3 Address Families: Enabled
OSPFv3 PE-CE: Enabled
OSPFv3 external path preference: Enabled
OSPFv3 Stub Router Advertisement: Enabled
OSPFv3 support of RFC3101: Enabled
`;

try {
  // Read the template
  const templateContent = fs.readFileSync(templatePath, 'utf8');

  // Create parser and parse the input
  console.log('Parsing with TextFSM...');
  const fsm = new TextFSM(templateContent);
  const result = fsm.parseText(sampleInput);

  console.log('Parsing successful!');
  console.log(`Parsed ${result.length} records`);
  console.log('\nResults:');
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error('Error:', error);
}