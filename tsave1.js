// TextFSM JavaScript implementation
class TextFSMError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TextFSMError';
  }
}

class TextFSMTemplateError extends TextFSMError {
  constructor(message) {
    super(message);
    this.name = 'TextFSMTemplateError';
  }
}

class TextFSMOptions {
  static ValidOptions() {
    return ['Required', 'Filldown', 'Fillup', 'Key', 'List'];
  }

  static GetOption(name) {
    switch(name) {
      case 'Required': return TextFSMOptions.Required;
      case 'Filldown': return TextFSMOptions.Filldown;
      case 'Fillup': return TextFSMOptions.Fillup;
      case 'Key': return TextFSMOptions.Key;
      case 'List': return TextFSMOptions.List;
      default: return null;
    }
  }

  static Required = class {
    constructor(value) {
      this.value = value;
      this.name = 'Required';
    }

    OnCreateOptions() {}
    OnClearVar() {}
    OnClearAllVar() {}
    OnAssignVar() {}
    OnGetValue() {}

    OnSaveRecord() {
      if (!this.value.value) {
        throw new SkipRecord();
      }
    }
  };

  static Filldown = class {
    constructor(value) {
      this.value = value;
      this.name = 'Filldown';
      this._myvar = null;
    }

    OnCreateOptions() {}

    OnAssignVar() {
      this._myvar = this.value.value;
    }

    OnClearVar() {
      this.value.value = this._myvar;
    }

    OnClearAllVar() {
      this._myvar = null;
    }

    OnGetValue() {}
    OnSaveRecord() {}
  };

  static Fillup = class {
    constructor(value) {
      this.value = value;
      this.name = 'Fillup';
    }

    OnCreateOptions() {}
    OnClearVar() {}
    OnClearAllVar() {}
    OnGetValue() {}
    OnSaveRecord() {}

    OnAssignVar() {
      // If value is set, copy up the results table, until we see a set item
      if (this.value.value) {
        // Get index of relevant result column
        const valueIdx = this.value.fsm.values.indexOf(this.value);

        // Go up the list from the end until we see a filled value
        const results = this.value.fsm._result;
        for (let i = results.length - 1; i >= 0; i--) {
          if (results[i][valueIdx]) {
            // Stop when a record has this column already
            break;
          }
          // Otherwise set the column value
          results[i][valueIdx] = this.value.value;
        }
      }
    }
  };

  static Key = class {
    constructor(value) {
      this.value = value;
      this.name = 'Key';
    }

    OnCreateOptions() {}
    OnClearVar() {}
    OnClearAllVar() {}
    OnAssignVar() {}
    OnGetValue() {}
    OnSaveRecord() {}
  };

  static List = class {
    constructor(value) {
      this.value = value;
      this.name = 'List';
    }

    OnCreateOptions() {
      this.OnClearAllVar();
    }

    OnAssignVar() {
      // Nested matches will have more than one match group
      let match = null;

      if (this.value.compiledRegex && this.value.compiledRegex.source.includes('(?<')) {
        match = this.value.compiledRegex.exec(this.value.value);
      }

      // If the List-value regex has match-groups defined, add the resulting
      // dict to the list. Otherwise, add the string that was matched
      if (match && Object.keys(match.groups).length > 1) {
        // Create a copy of the groups object, excluding the main capture group
        const groups = { ...match.groups };
        // If the main group name is the same as the value name, remove it
        if (groups[this.value.name]) {
          delete groups[this.value.name];
        }
        this._value.push(groups);
      } else {
        this._value.push(this.value.value);
      }
    }

    OnClearVar() {
      // Check if Filldown is present in options
      const hasFilldown = this.value.options.some(option => option.name === 'Filldown');

      if (!hasFilldown) {
        this._value = [];
      }
    }

    OnClearAllVar() {
      this._value = [];
    }

    OnGetValue() {}

    OnSaveRecord() {
      this.value.value = [...this._value]; // Create a copy of the list
    }
  };
}

class TextFSMValue {
  constructor(fsm = null, maxNameLen = 48, optionsClass = null) {
    this.maxNameLen = maxNameLen;
    this.name = null;
    this.options = [];
    this.regex = null;
    this.value = null;
    this.fsm = fsm;
    this._options_cls = optionsClass || TextFSMOptions;
  }

  AssignVar(value) {
    this.value = value;
    this.options.forEach(option => option.OnAssignVar());
  }

  ClearVar() {
    this.value = null;
    this.options.forEach(option => option.OnClearVar());
  }

  ClearAllVar() {
    this.value = null;
    this.options.forEach(option => option.OnClearAllVar());
  }

  Header() {
    this.options.forEach(option => option.OnGetValue());
    return this.name;
  }

  OptionNames() {
    return this.options.map(option => option.name);
  }

  Parse(value) {
    const valueLine = value.split(' ');
    if (valueLine.length < 3) {
      throw new TextFSMTemplateError('Expect at least 3 tokens on line.');
    }

    if (!valueLine[2].startsWith('(')) {
      // Options are present
      const options = valueLine[1];
      options.split(',').forEach(option => {
        this._AddOption(option);
      });

      // Call option OnCreateOptions callbacks
      this.options.forEach(option => option.OnCreateOptions());

      this.name = valueLine[2];
      this.regex = valueLine.slice(3).join(' ');
    } else {
      // No options, treat argument as name
      this.name = valueLine[1];
      this.regex = valueLine.slice(2).join(' ');
    }

    if (this.name.length > this.maxNameLen) {
      throw new TextFSMTemplateError(`Invalid Value name '${this.name}' or name too long.`);
    }

    if (this.regex[0] !== '(' || this.regex[this.regex.length - 1] !== ')' || this.regex[this.regex.length - 2] === '\\') {
      throw new TextFSMTemplateError(`Value '${this.regex}' must be contained within a '()' pair.`);
    }

    try {
      // Convert Python's (?P<name>pattern) to JavaScript's (?<name>pattern)
      const jsRegex = this.regex.replace(/\(\?P<(\w+)>/g, '(?<$1>');
      this.compiledRegex = new RegExp(jsRegex);
    } catch (e) {
      throw new TextFSMTemplateError(e.message);
    }

    // Replace Python's named groups with JavaScript's named groups
this.template = this.regex.replace(/^\(/, `(?<${this.name}>`);
  }

  _AddOption(name) {
    // Check for duplicate option declaration
    if (this.options.some(option => option.name === name)) {
      throw new TextFSMTemplateError(`Duplicate option "${name}"`);
    }

    // Create option object
    const OptionClass = this._options_cls.GetOption(name);
    if (!OptionClass) {
      throw new TextFSMTemplateError(`Unknown option "${name}"`);
    }

    const option = new OptionClass(this);
    this.options.push(option);
  }

  OnSaveRecord() {
    this.options.forEach(option => option.OnSaveRecord());
  }

  toString() {
    if (this.options.length) {
      return `Value ${this.OptionNames().join(',')} ${this.name} ${this.regex}`;
    } else {
      return `Value ${this.name} ${this.regex}`;
    }
  }
}

class TextFSMRule {
  // Match actions and operators similar to Python version
  static MATCH_ACTION = /(?<match>.*)(\s->(?<action>.*))/;
  static LINE_OP = ['Continue', 'Next', 'Error'];
  static RECORD_OP = ['Clear', 'Clearall', 'Record', 'NoRecord'];

  // Create regex patterns similar to Python version, with JS regex syntax
  static LINE_OP_RE = `(?<ln_op>${TextFSMRule.LINE_OP.join('|')})`;
  static RECORD_OP_RE = `(?<rec_op>${TextFSMRule.RECORD_OP.join('|')})`;
  static OPERATOR_RE = `(${TextFSMRule.LINE_OP_RE}(\\.${TextFSMRule.RECORD_OP_RE})?)`;
  static NEWSTATE_RE = `(?<new_state>\\w+|".*")`;

  // Compile regex patterns
  static ACTION_RE = new RegExp(`\\s+${TextFSMRule.OPERATOR_RE}(\\s+${TextFSMRule.NEWSTATE_RE})?$`);
  static ACTION2_RE = new RegExp(`\\s+${TextFSMRule.RECORD_OP_RE}(\\s+${TextFSMRule.NEWSTATE_RE})?$`);
  static ACTION3_RE = new RegExp(`(\\s+${TextFSMRule.NEWSTATE_RE})?$`);

  constructor(line, lineNum = -1, varMap = null) {
    this.match = '';
    this.regex = '';
    this.regexObj = null;
    this.lineOp = '';  // Equivalent to 'Next'
    this.recordOp = '';  // Equivalent to 'NoRecord'
    this.newState = '';  // Equivalent to current state
    this.lineNum = lineNum;

    line = line.trim();
    if (!line) {
      throw new TextFSMTemplateError(`Null data in FSMRule. Line: ${this.lineNum}`);
    }

    // Check for -> action
    const matchAction = TextFSMRule.MATCH_ACTION.exec(line);
    if (matchAction) {
      this.match = matchAction.groups.match;
    } else {
      this.match = line;
    }

    // Replace ${varname} entries (template substitution)
    this.regex = this.match;
if (varMap) {
  try {
    this.regex = this.match.replace(/\${(\w+)}/g, (match, name) => {
      if (varMap[name] === undefined) {
        throw new TextFSMTemplateError(
          `Invalid variable substitution: '${name}'. Line: ${this.lineNum}`
        );
      }
      return varMap[name];
    });
  } catch (e) {
    throw new TextFSMTemplateError(
      `Error in template substitution. Line: ${this.lineNum}. ${e.message}`
    );
  }
}

    try {
      // Convert Python regex to JavaScript regex
      const jsRegex = this.regex.replace(/\(\?P<(\w+)>/g, '(?<$1>');
      // Use CopyableRegexObject instead of direct RegExp
      this.regexObj = new CopyableRegexObject(jsRegex);
    } catch (e) {
      throw new TextFSMTemplateError(`Invalid regular expression: '${this.regex}'. Line: ${this.lineNum}`);
    }

    // No -> present, so we're done
    if (!matchAction) {
      return;
    }

    // Process action part
    const action = matchAction.groups.action;
    let actionRe = TextFSMRule.ACTION_RE.exec(action);

    if (!actionRe) {
      actionRe = TextFSMRule.ACTION2_RE.exec(action);

      if (!actionRe) {
        actionRe = TextFSMRule.ACTION3_RE.exec(action);

        if (!actionRe) {
          throw new TextFSMTemplateError(`Badly formatted rule '${line}'. Line: ${this.lineNum}`);
        }
      }
    }

    // Process line operator
    if (actionRe.groups && actionRe.groups.ln_op) {
      this.lineOp = actionRe.groups.ln_op;
    }

    // Process record operator
    if (actionRe.groups && actionRe.groups.rec_op) {
      this.recordOp = actionRe.groups.rec_op;
    }

    // Process new state
    if (actionRe.groups && actionRe.groups.new_state) {
      this.newState = actionRe.groups.new_state;
    }

    // Validate: only 'Next' line operator can have a new_state
    if (this.lineOp === 'Continue' && this.newState) {
      throw new TextFSMTemplateError(`Action '${this.lineOp}' with new state ${this.newState} specified. Line: ${this.lineNum}`);
    }

    // Validate state name
    if (this.lineOp !== 'Error' && this.newState) {
      if (!/^\w+$/.test(this.newState)) {
        throw new TextFSMTemplateError(`Alphanumeric characters only in state names. Line: ${this.lineNum}`);
      }
    }
  }

  toString() {
    let operation = '';
    if (this.lineOp && this.recordOp) {
      operation = '.';
    }

    operation = `${this.lineOp}${operation}${this.recordOp}`;

    const newState = operation && this.newState ? ` ${this.newState}` : this.newState;

    // Print with implicit defaults
    if (!(operation || newState)) {
      return `  ${this.match}`;
    }

    // Non defaults
    return `  ${this.match} -> ${operation}${newState}`;
  }
}

class TextFSM {
  constructor(template, optionsClass = TextFSMOptions) {
    this.MAX_NAME_LEN = 48;
    this._options_cls = optionsClass;
    this.states = {};
    this.stateList = [];
    this.values = [];
    this.valueMap = {};
    this._lineNum = 0;
    this._curState = null;
    this._curStateName = null;

    // Parse the template (assuming template is a string)
    this._parse(template);

    // Initialize starting data
    this.reset();
  }

  reset() {
    // Set current state to Start
    this._curState = this.states['Start'];
    this._curStateName = 'Start';

    // Clear results and current record
    this._result = [];
    this._clearAllRecord();
  }

  get header() {
    return this._getHeader();
  }

  _getHeader() {
    return this.values.map(value => {
      try {
        return value.Header();
      } catch (e) {
        if (e instanceof SkipValue) {
          return null;
        }
        throw e;
      }
    }).filter(h => h !== null);
  }

  _getValue(name) {
    return this.values.find(value => value.name === name);
  }

  _appendRecord() {
    // If no values then don't output
    if (!this.values.length) {
      return;
    }

    const curRecord = [];
    for (const value of this.values) {
      try {
        value.OnSaveRecord();
      } catch (e) {
        if (e instanceof SkipRecord) {
          this._clearRecord();
          return;
        }
        if (e instanceof SkipValue) {
          continue;
        }
        throw e;
      }

      // Build current record
      curRecord.push(value.value);
    }

    // If no values in template or whole record is empty, don't output
    if (curRecord.length === 0 ||
        curRecord.every(val => val === null || (Array.isArray(val) && val.length === 0))) {
      return;
    }

    // Replace null entries with empty string
    for (let i = 0; i < curRecord.length; i++) {
      if (curRecord[i] === null) {
        curRecord[i] = '';
      }
    }

    this._result.push(curRecord);
    this._clearRecord();
  }

  _parse(template) {
    if (!template) {
      throw new TextFSMTemplateError('Null template.');
    }

    // Handle potential encoding issues by ensuring we have a string
    let templateStr = template;

    // If input is ArrayBuffer or TypedArray, convert to string
    if (template instanceof ArrayBuffer ||
        (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView(template))) {
      try {
        templateStr = new TextDecoder('utf-8').decode(template);
      } catch (e) {
        // Fallback for environments without TextDecoder
        templateStr = String.fromCharCode.apply(null,
          new Uint8Array(template instanceof ArrayBuffer ? template : template.buffer));
      }
    }

    // Split template into lines, handling different line endings
    const lines = templateStr.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');

    // Parse Variables section
    let lineIndex = this._parseVariables(lines);

    // Parse States
    while (lineIndex < lines.length) {
      lineIndex = this._parseState(lines, lineIndex);
    }

    // Validate FSM
    this._validateFSM();
  }

  _parseVariables(lines) {
    this.values = [];
    let lineIndex = 0;

    for (; lineIndex < lines.length; lineIndex++) {
      this._lineNum = lineIndex + 1;
      const line = lines[lineIndex].trim();

      // Blank line signifies end of Value definitions
      if (!line) {
        return lineIndex + 1;
      }

      // Skip commented lines
      if (line.startsWith('#')) {
        continue;
      }

      if (line.startsWith('Value ')) {
        try {
          const value = new TextFSMValue(
            this,
            this.MAX_NAME_LEN,
            this._options_cls
          );
          value.Parse(line);

          if (this.header.includes(value.name)) {
            throw new TextFSMTemplateError(
              `Duplicate declarations for Value '${value.name}'. Line: ${this._lineNum}`
            );
          }

          this._validateOptions(value);
          this.values.push(value);
          this.valueMap[value.name] = value.template;
        } catch (e) {
          if (e instanceof TextFSMTemplateError) {
            throw new TextFSMTemplateError(`${e.message} Line ${this._lineNum}.`);
          }
          throw e;
        }
      } else if (!this.values.length) {
        throw new TextFSMTemplateError('No Value definitions found.');
      } else {
        throw new TextFSMTemplateError(
          `Expected blank line after last Value entry. Line: ${this._lineNum}.`
        );
      }
    }

    return lineIndex;
  }

  _validateOptions(value) {
    // Check for incompatible options
    const options = value.OptionNames();

    // Cannot have both Key and List
    if (options.includes('Key') && options.includes('List')) {
      throw new TextFSMTemplateError(`Value cannot have both 'Key' and 'List' options: '${value.name}'`);
    }

    // Cannot have both Filldown and Fillup
    if (options.includes('Filldown') && options.includes('Fillup')) {
      throw new TextFSMTemplateError(`Value cannot have both 'Filldown' and 'Fillup' options: '${value.name}'`);
    }

    // Additional validation can be added here
  }

  _parseState(lines, startIndex) {
    let lineIndex = startIndex;
    let stateName = '';

    // Find state definition
    for (; lineIndex < lines.length; lineIndex++) {
      this._lineNum = lineIndex + 1;
      const line = lines[lineIndex].trim();

      // Skip blank lines and comments
      if (!line || line.startsWith('#')) {
        continue;
      }

      // First non-blank, non-comment line is state definition
      const stateNameRe = /^(\w+)$/;
      if (!stateNameRe.test(line) ||
          line.length > this.MAX_NAME_LEN ||
          TextFSMRule.LINE_OP.includes(line) ||
          TextFSMRule.RECORD_OP.includes(line)) {
        throw new TextFSMTemplateError(
          `Invalid state name: '${line}'. Line: ${this._lineNum}`
        );
      }

      stateName = line;
      if (stateName in this.states) {
        throw new TextFSMTemplateError(
          `Duplicate state name: '${line}'. Line: ${this._lineNum}`
        );
      }

      this.states[stateName] = [];
      this.stateList.push(stateName);
      lineIndex++;
      break;
    }

    if (!stateName) {
      return lines.length; // End of file
    }

    // Parse rules in this state
    for (; lineIndex < lines.length; lineIndex++) {
      this._lineNum = lineIndex + 1;
      const line = lines[lineIndex];

      // Blank line ends the state
      // Blank line ends the state
if (!line.trim()) {
  return lineIndex + 1;
}

      // Skip comments
      if (line.startsWith('#')) {
        continue;
      }

      // Check rule format
      // Alternative implementation with array.some()
const hasValidPrefix = [' ^', '  ^', '\t^'].some(prefix => line.startsWith(prefix));
if (!hasValidPrefix) {
  throw new TextFSMTemplateError(
    `Missing white space or carat ('^') before rule. Line: ${this._lineNum}`
  );
}


      // Add rule to state
      this.states[stateName].push(
        new TextFSMRule(line, this._lineNum, this.valueMap)
      );
    }

    return lines.length; // End of file
  }

  _validateFSM() {
    // Must have 'Start' state
    if (!('Start' in this.states)) {
      throw new TextFSMTemplateError("Missing state 'Start'.");
    }

    // 'End/EOF' state (if specified) must be empty
    if (this.states['End'] && this.states['End'].length > 0) {
      throw new TextFSMTemplateError("Non-Empty 'End' state.");
    }

    if (this.states['EOF'] && this.states['EOF'].length > 0) {
      throw new TextFSMTemplateError("Non-Empty 'EOF' state.");
    }

    // Remove 'End' state
    if ('End' in this.states) {
      delete this.states['End'];
      this.stateList = this.stateList.filter(state => state !== 'End');
    }

    // Ensure jump states are all valid
    for (const state in this.states) {
      for (const rule of this.states[state]) {
        if (rule.lineOp === 'Error') {
          continue;
        }

        if (!rule.newState || rule.newState === 'End' || rule.newState === 'EOF') {
          continue;
        }

        if (!(rule.newState in this.states)) {
          throw new TextFSMTemplateError(
            `State '${rule.newState}' not found, referenced in state '${state}'`
          );
        }
      }
    }

    return true;
  }

  parseText(text, eof = true) {
    if (!text) {
      return this._result;
    }

    // Normalize line endings and handle encoding
    let processedText = text;
    if (typeof text !== 'string') {
      try {
        processedText = new TextDecoder('utf-8').decode(text);
      } catch (e) {
        // Fallback for older browsers
        processedText = text.toString();
      }
    }

    // Split text into lines, handling different line endings
    const lines = processedText.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');

    // Process each line
    for (const line of lines) {
      this._processLine(line);
      if (this._curStateName === 'End' || this._curStateName === 'EOF') {
        break;
      }
    }

    // Implicit EOF if needed
    if (this._curStateName !== 'End' && !('EOF' in this.states) && eof) {
      this._appendRecord();
    }

    return this._result;
  }

  _processLine(line) {
    // Pre-process the line before checking rules
    const trimmedLine = this._preprocessLine(line);
    this._checkLine(trimmedLine);
  }

  _preprocessLine(line) {
    // Remove trailing whitespace
    // This better matches Python's behavior when handling lines
    return line.replace(/\s+$/, '');
  }

  parseTextToDicts(text, eof = true) {
    const resultLists = this.parseText(text, eof);
    return resultLists.map(row => {
      const dict = {};
      for (let i = 0; i < this.header.length; i++) {
        dict[this.header[i]] = row[i];
      }
      return dict;
    });
  }

  _checkLine(line) {
    for (const rule of this._curState) {
      const matched = this._checkRule(rule, line);
      if (matched) {
        // Process captured groups
        for (const value in matched.groups) {
          this._assignVar(matched, value);
        }

        if (this._operations(rule, line)) {
          // Not a Continue, so check for state transition
          if (rule.newState) {
            if (rule.newState !== 'End' && rule.newState !== 'EOF') {
              this._curState = this.states[rule.newState];
            }
            this._curStateName = rule.newState;
          }
          break;
        }
      }
    }
  }

  _checkRule(rule, line) {
    // This is a separate method so it can be overridden for debugging
    return rule.regexObj.match(line);
  }

  _assignVar(matched, value) {
    const fsm_value = this._getValue(value);
    if (fsm_value) {
      fsm_value.AssignVar(matched.groups[value]);
    }
  }

  _operations(rule, line) {
    // Process record operators
    if (rule.recordOp === 'Record') {
      this._appendRecord();
    } else if (rule.recordOp === 'Clear') {
      this._clearRecord();
    } else if (rule.recordOp === 'Clearall') {
      this._clearAllRecord();
    }

    // Process line operators
    if (rule.lineOp === 'Error') {
      if (rule.newState) {
        throw new TextFSMError(
          `Error: ${rule.newState}. Rule Line: ${rule.lineNum}. Input Line: ${line}.`
        );
      }
      throw new TextFSMError(
        `State Error raised. Rule Line: ${rule.lineNum}. Input Line: ${line}.`
      );
    } else if (rule.lineOp === 'Continue') {
      // Continue with current line
      return false;
    }

    // Return to start of current state with new line
    return true;
  }

  _clearRecord() {
    // Remove non-Filldown record entries
    this.values.forEach(value => value.ClearVar());
  }

  _clearAllRecord() {
    // Remove all record entries
    this.values.forEach(value => value.ClearAllVar());
  }

  getValuesByAttrib(attribute) {
    if (!this._options_cls.ValidOptions().includes(attribute)) {
      throw new Error(`'${attribute}': Not a valid attribute.`);
    }

    return this.values
      .filter(value => value.OptionNames().includes(attribute))
      .map(value => value.name);
  }

  toString() {
    let result = this.values.map(value => value.toString()).join('\n');
    result += '\n';

    for (const state of this.stateList) {
      result += `\n${state}\n`;
      if (this.states[state].length) {
        result += this.states[state].map(rule => rule.toString()).join('\n') + '\n';
      }
    }

    return result;
  }
}

// CopyableRegexObject implementation
class CopyableRegexObject {
  constructor(pattern) {
    this.pattern = pattern;
    this.regex = new RegExp(pattern);
  }

  exec(str) {
    return this.regex.exec(str);
  }

  test(str) {
    return this.regex.test(str);
  }

  match(str) {
    // JavaScript doesn't have direct match method, simulate it
    const result = this.regex.exec(str);
    return result && result.index === 0 ? result : null;
  }

  replace(str, newSubStr) {
    return str.replace(this.regex, newSubStr);
  }

  clone() {
    return new CopyableRegexObject(this.pattern);
  }
}

// Helper exception classes
class FSMAction extends Error {
  constructor(message) {
    super(message);
    this.name = 'FSMAction';
  }
}

class SkipRecord extends FSMAction {
  constructor(message) {
    super(message);
    this.name = 'SkipRecord';
  }
}

class SkipValue extends FSMAction {
  constructor(message) {
    super(message);
    this.name = 'SkipValue';
  }
}

// Export the module for browser use
const TextFSMModule = {
  TextFSM,
  TextFSMValue,
  TextFSMRule,
  TextFSMOptions,
  TextFSMError,
  TextFSMTemplateError
};

// Make it available in the global scope
window.TextFSM = TextFSMModule;