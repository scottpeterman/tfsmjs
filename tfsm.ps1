# TextFSM.psm1 - PowerShell Module for TextFSM

#region Exception Classes
class TextFSMError : System.Exception {
    TextFSMError([string]$message) : base($message) {
        $this.Source = "TextFSM"
    }
}

class TextFSMTemplateError : TextFSMError {
    TextFSMTemplateError([string]$message) : base($message) {
        $this.Source = "TextFSMTemplate"
    }
}

class SkipRecord : System.Exception {
    SkipRecord([string]$message) : base($message) {
        $this.Source = "TextFSM"
    }
}

class SkipValue : System.Exception {
    SkipValue([string]$message) : base($message) {
        $this.Source = "TextFSM"
    }
}
#endregion

#region Option Classes
class TextFSMOptions {
    static [string[]] ValidOptions() {
        return @('Required', 'Filldown', 'Fillup', 'Key', 'List')
    }

    static [object] GetOption([string]$name, [object]$value) {
        switch($name) {
            'Required' { return [RequiredOption]::new($value) }
            'Filldown' { return [FilldownOption]::new($value) }
            'Fillup' { return [FillupOption]::new($value) }
            'Key' { return [KeyOption]::new($value) }
            'List' { return [ListOption]::new($value) }
            default { return $null }
        }
    }
}

class RequiredOption {
    [object]$value
    [string]$name = 'Required'

    RequiredOption([object]$value) {
        $this.value = $value
    }

    [void] OnCreateOptions() {}
    [void] OnClearVar() {}
    [void] OnClearAllVar() {}
    [void] OnAssignVar() {}
    [void] OnGetValue() {}

    [void] OnSaveRecord() {
        # For List values, check if the list is empty
        if ($this.value.value -is [array] -and $this.value.value.Count -eq 0) {
            throw [SkipRecord]::new("Required value '$($this.value.name)' has no entries")
        }
        # For scalar values, check if the value is null or empty
        elseif ($null -eq $this.value.value -or $this.value.value -eq '') {
            throw [SkipRecord]::new("Required value '$($this.value.name)' is empty")
        }
    }
}

class FilldownOption {
    [object]$value
    [string]$name = 'Filldown'
    [object]$_myvar = $null

    FilldownOption([object]$value) {
        $this.value = $value
    }

    [void] OnCreateOptions() {}

    [void] OnAssignVar() {
        $this._myvar = $this.value.value
    }

    [void] OnClearVar() {
        $this.value.value = $this._myvar
    }

    [void] OnClearAllVar() {
        $this._myvar = $null
    }

    [void] OnGetValue() {}
    [void] OnSaveRecord() {}
}

class FillupOption {
    [object]$value
    [string]$name = 'Fillup'

    FillupOption([object]$value) {
        $this.value = $value
    }

    [void] OnCreateOptions() {}
    [void] OnClearVar() {}
    [void] OnClearAllVar() {}
    [void] OnGetValue() {}
    [void] OnSaveRecord() {}

    [void] OnAssignVar() {
        # If value is set, copy up the results table, until we see a set item
        if ($null -ne $this.value.value) {
            # Get index of relevant result column
            $valueIdx = $this.value.fsm.values.IndexOf($this.value)

            # Go up the list from the end until we see a filled value
            $results = $this.value.fsm._result
            for ($i = $results.Count - 1; $i -ge 0; $i--) {
                if ($null -ne $results[$i][$valueIdx] -and $results[$i][$valueIdx] -ne '') {
                    # Stop when a record has this column already
                    break
                }
                # Otherwise set the column value
                $results[$i][$valueIdx] = $this.value.value
            }
        }
    }
}

class KeyOption {
    [object]$value
    [string]$name = 'Key'

    KeyOption([object]$value) {
        $this.value = $value
    }

    [void] OnCreateOptions() {}
    [void] OnClearVar() {}
    [void] OnClearAllVar() {}
    [void] OnAssignVar() {}
    [void] OnGetValue() {}

    [void] OnSaveRecord() {
        # Skip if the value is empty
        if ($null -eq $this.value.value -or $this.value.value -eq '') {
            return
        }

        # Get all values with Key option to form a composite key
        $keyValues = $this.value.fsm.values |
            Where-Object { $_.OptionNames() -contains 'Key' } |
            ForEach-Object { $_.value }

        # Create a string key for the Set
        $keyString = ConvertTo-Json -InputObject $keyValues -Compress

        # Check if this key has been seen before
        if ($this.value.fsm._seenKeys.Contains($keyString)) {
            throw [SkipRecord]::new("Duplicate key: $keyString")
        }

        # Add the key to the seen keys set
        [void]$this.value.fsm._seenKeys.Add($keyString)
    }
}

class ListOption {
    [object]$value
    [string]$name = 'List'
    [array]$_value = @()

    ListOption([object]$value) {
        $this.value = $value
    }

    [void] OnCreateOptions() {
        $this.OnClearAllVar()
    }

    [void] OnAssignVar() {
        # Check if the regex has named capture groups
        # In PowerShell, we can check the GroupNames collection
        $match = $null

        # Get the match object from a test match
        if ($this.value.compiledRegex) {
            $match = $this.value.compiledRegex.Match($this.value.value)
        }

        # If the List-value regex has match-groups defined, add the resulting
        # dict to the list. Otherwise, add the string that was matched
        if ($match -and $match.Groups.Count > 2) {
            # Create a hashtable for the groups, excluding the main capture group
            $groups = @{}
            foreach ($groupName in $match.Groups.Keys | Where-Object { $_ -match '^\w+$' -and $_ -ne '0' -and $_ -ne $this.value.name }) {
                $groups[$groupName] = $match.Groups[$groupName].Value
            }
            $this._value += $groups
        } else {
            $this._value += $this.value.value
        }
    }

    [void] OnClearVar() {
        # Check if Filldown is present in options
        $hasFilldown = $this.value.options | Where-Object { $_.name -eq 'Filldown' }

        if (-not $hasFilldown) {
            $this._value = @()
        }
        # When Filldown is present, keep the current values
    }

    [void] OnClearAllVar() {
        $this._value = @()
    }

    [void] OnGetValue() {}

    [void] OnSaveRecord() {
        # Create a copy of the list
        $this.value.value = @() + $this._value
    }
}
#endregion

#region Value and Rule Classes
class TextFSMValue {
    [int]$maxNameLen = 48
    [string]$name
    [array]$options = @()
    [string]$regex
    [System.Text.RegularExpressions.Regex]$compiledRegex
    [string]$template
    [object]$value = $null
    [object]$fsm
    [object]$_options_cls

    TextFSMValue([object]$fsm = $null, [int]$maxNameLen = 48, [object]$optionsClass = $null) {
        $this.maxNameLen = $maxNameLen
        $this.fsm = $fsm
        $this._options_cls = $optionsClass
        if ($null -eq $this._options_cls) {
            $this._options_cls = [TextFSMOptions]
        }
    }

    [void] AssignVar([object]$value) {
        $this.value = $value
        foreach ($option in $this.options) {
            $option.OnAssignVar()
        }
    }

    [void] ClearVar() {
        $this.value = $null
        foreach ($option in $this.options) {
            $option.OnClearVar()
        }
    }

    [void] ClearAllVar() {
        $this.value = $null
        foreach ($option in $this.options) {
            $option.OnClearAllVar()
        }
    }

    [string] Header() {
        foreach ($option in $this.options) {
            $option.OnGetValue()
        }
        return $this.name
    }

    [string[]] OptionNames() {
        return $this.options | ForEach-Object { $_.name }
    }

    [void] Parse([string]$value) {
        $valueLine = $value -split ' '
        if ($valueLine.Count -lt 3) {
            throw [TextFSMTemplateError]::new('Expect at least 3 tokens on line.')
        }

        if (-not $valueLine[2].StartsWith('(')) {
            # Options are present
            $options = $valueLine[1]
            foreach ($option in $options -split ',') {
                $this._AddOption($option)
            }

            # Call option OnCreateOptions callbacks
            foreach ($option in $this.options) {
                $option.OnCreateOptions()
            }

            $this.name = $valueLine[2]
            $this.regex = ($valueLine[3..($valueLine.Count-1)] -join ' ')
        } else {
            # No options, treat argument as name
            $this.name = $valueLine[1]
            $this.regex = ($valueLine[2..($valueLine.Count-1)] -join ' ')
        }

        if ($this.name.Length -gt $this.maxNameLen) {
            throw [TextFSMTemplateError]::new("Invalid Value name '$($this.name)' or name too long.")
        }

        if ($this.regex[0] -ne '(' -or $this.regex[-1] -ne ')' -or $this.regex[-2] -eq '\') {
            throw [TextFSMTemplateError]::new("Value '$($this.regex)' must be contained within a '()' pair.")
        }

        try {
            # Convert Python's (?P<name>pattern) to .NET's (?<name>pattern)
            $netRegex = $this.regex -replace '\(\?P<(\w+)>', '(?<$1>'
            $this.compiledRegex = [System.Text.RegularExpressions.Regex]::new($netRegex)
        } catch {
            throw [TextFSMTemplateError]::new($_.Exception.Message)
        }

        # Replace Python's named groups with .NET's named groups
        $this.template = $this.regex -replace '^\(', "(?<$($this.name)>"
    }

    [void] _AddOption([string]$name) {
        # Check for duplicate option declaration
        if ($this.options | Where-Object { $_.name -eq $name }) {
            throw [TextFSMTemplateError]::new("Duplicate option `"$name`"")
        }

        # Create option object
        $optionClass = $this._options_cls::GetOption($name, $this)
        if ($null -eq $optionClass) {
            throw [TextFSMTemplateError]::new("Unknown option `"$name`"")
        }

        $this.options += $optionClass
    }

    [void] OnSaveRecord() {
        foreach ($option in $this.options) {
            $option.OnSaveRecord()
        }
    }

    [string] ToString() {
        if ($this.options.Count) {
            return "Value $($this.OptionNames() -join ',') $($this.name) $($this.regex)"
        } else {
            return "Value $($this.name) $($this.regex)"
        }
    }
}

class TextFSMRule {
    # Constants
    static [string]$MATCH_ACTION_PATTERN = '(?<match>.*?)(\s->(?<action>.*))'
    static [string[]]$LINE_OP = @('Continue', 'Next', 'Error')
    static [string[]]$RECORD_OP = @('Clear', 'Clearall', 'Record', 'NoRecord')

    # Regex patterns for action parsing
    static [string]$LINE_OP_RE = "(?<ln_op>$([TextFSMRule]::LINE_OP -join '|'))"
    static [string]$RECORD_OP_RE = "(?<rec_op>$([TextFSMRule]::RECORD_OP -join '|'))"
    static [string]$OPERATOR_RE = "($([TextFSMRule]::LINE_OP_RE)(\\.$([TextFSMRule]::RECORD_OP_RE))?)?"
    static [string]$NEWSTATE_RE = "(?<new_state>\\w+|\".*\")"

    # Compiled action regex patterns
    static [regex]$ACTION_RE = [regex]::new("\\s+$([TextFSMRule]::OPERATOR_RE)(\\s+$([TextFSMRule]::NEWSTATE_RE))?$")
    static [regex]$ACTION2_RE = [regex]::new("\\s+$([TextFSMRule]::RECORD_OP_RE)(\\s+$([TextFSMRule]::NEWSTATE_RE))?$")
    static [regex]$ACTION3_RE = [regex]::new("(\\s+$([TextFSMRule]::NEWSTATE_RE))?$")

    [string]$match = ''
    [string]$regex = ''
    [System.Text.RegularExpressions.Regex]$regexObj
    [string]$lineOp = ''  # Equivalent to 'Next'
    [string]$recordOp = ''  # Equivalent to 'NoRecord'
    [string]$newState = ''  # Equivalent to current state
    [int]$lineNum = -1
    [bool]$multiline = $false  # Flag for multi-line patterns

    TextFSMRule([string]$line, [int]$lineNum = -1, [hashtable]$varMap = $null) {
        $this.lineNum = $lineNum

        $trimmedLine = $line.Trim()
        if (-not $trimmedLine) {
            throw [TextFSMTemplateError]::new("Null data in FSMRule. Line: $($this.lineNum)")
        }

        # Check for -> action
        $matchAction = [regex]::Match($trimmedLine, [TextFSMRule]::MATCH_ACTION_PATTERN)
        if ($matchAction.Success) {
            $this.match = $matchAction.Groups['match'].Value
        } else {
            $this.match = $trimmedLine
        }

        # Replace ${varname} entries (template substitution)
        $this.regex = $this.match
        if ($null -ne $varMap) {
            try {
                $this.regex = [regex]::Replace($this.match, '\${(\w+)}', {
                    param($m)
                    $name = $m.Groups[1].Value
                    if (-not $varMap.ContainsKey($name)) {
                        throw [TextFSMTemplateError]::new(
                            "Invalid variable substitution: '$name'. Line: $($this.lineNum)"
                        )
                    }
                    return $varMap[$name]
                })
            } catch {
                throw [TextFSMTemplateError]::new(
                    "Error in template substitution. Line: $($this.lineNum). $($_.Exception.Message)"
                )
            }
        }

        # Check if this is a multi-line pattern (contains \n)
        $this.multiline = $this.regex.Contains('\n')

        try {
            # Convert Python regex to .NET regex
            $netRegex = $this.regex -replace '\(\?P<(\w+)>', '(?<$1>'
            # Use RegexOptions for multi-line patterns
            $regexOptions = if ($this.multiline) { [System.Text.RegularExpressions.RegexOptions]::Singleline } else { [System.Text.RegularExpressions.RegexOptions]::None }
            $this.regexObj = [System.Text.RegularExpressions.Regex]::new($netRegex, $regexOptions)
        } catch {
            throw [TextFSMTemplateError]::new("Invalid regular expression: '$($this.regex)'. Line: $($this.lineNum)")
        }

        # No -> present, so we're done
        if (-not $matchAction.Success) {
            return
        }

        # Process action part
        $action = $matchAction.Groups['action'].Value
        $actionRe = [TextFSMRule]::ACTION_RE.Match($action)

        if (-not $actionRe.Success) {
            $actionRe = [TextFSMRule]::ACTION2_RE.Match($action)

            if (-not $actionRe.Success) {
                $actionRe = [TextFSMRule]::ACTION3_RE.Match($action)

                if (-not $actionRe.Success) {
                    throw [TextFSMTemplateError]::new("Badly formatted rule '$trimmedLine'. Line: $($this.lineNum)")
                }
            }
        }

        # Process line operator
        if ($actionRe.Groups['ln_op'].Success) {
            $this.lineOp = $actionRe.Groups['ln_op'].Value
        }

        # Process record operator
        if ($actionRe.Groups['rec_op'].Success) {
            $this.recordOp = $actionRe.Groups['rec_op'].Value
        }

        # Process new state
        if ($actionRe.Groups['new_state'].Success) {
            $this.newState = $actionRe.Groups['new_state'].Value
        }

        # Validate: only 'Next' line operator can have a new_state
        if ($this.lineOp -eq 'Continue' -and $this.newState) {
            throw [TextFSMTemplateError]::new("Action '$($this.lineOp)' with new state $($this.newState) specified. Line: $($this.lineNum)")
        }

        # Validate state name
        if ($this.lineOp -ne 'Error' -and $this.newState) {
            if (-not ($this.newState -match '^\w+$')) {
                throw [TextFSMTemplateError]::new("Alphanumeric characters only in state names. Line: $($this.lineNum)")
            }
        }
    }

    [string] ToString() {
        $operation = ''
        if ($this.lineOp -and $this.recordOp) {
            $operation = '.'
        }

        $operation = "$($this.lineOp)$($operation)$($this.recordOp)"

        $newState = if ($operation -and $this.newState) { " $($this.newState)" } else { $this.newState }

        # Print with implicit defaults
        if (-not ($operation -or $newState)) {
            return "  $($this.match)"
        }

        # Non defaults
        return "  $($this.match) -> $($operation)$($newState)"
    }
}
#endregion

#region TextFSM Class
class TextFSM {
    [int]$MAX_NAME_LEN = 48
    [object]$_options_cls
    [hashtable]$states = @{}
    [array]$stateList = @()
    [array]$values = @()
    [hashtable]$valueMap = @{}
    [int]$_lineNum = 0
    [array]$_curState
    [string]$_curStateName
    [System.Collections.Generic.HashSet[string]]$_seenKeys
    [array]$_result = @()

    TextFSM([string]$template, [object]$optionsClass = [TextFSMOptions]) {
        $this._options_cls = $optionsClass
        $this._seenKeys = [System.Collections.Generic.HashSet[string]]::new()

        # Parse the template
        $this._parse($template)

        # Initialize starting data
        $this.reset()
    }

    [void] reset() {
        # Set current state to Start
        $this._curState = $this.states['Start']
        $this._curStateName = 'Start'

        # Clear results and current record
        $this._result = @()
        $this._seenKeys.Clear()
        $this._clearAllRecord()
    }

    [array] header() {
        return $this._getHeader()
    }

    [array] _getHeader() {
        $headers = @()
        foreach ($value in $this.values) {
            try {
                $headers += $value.Header()
            } catch [SkipValue] {
                # Skip this value
            } catch {
                throw
            }
        }
        return $headers
    }

    [object] _getValue([string]$name) {
        return $this.values | Where-Object { $_.name -eq $name } | Select-Object -First 1
    }

    [void] _appendRecord() {
        # If no values then don't output
        if (-not $this.values.Count) {
            return
        }

        $curRecord = @()
        try {
            foreach ($value in $this.values) {
                try {
                    $value.OnSaveRecord()
                } catch [SkipRecord] {
                    $this._clearRecord()
                    return
                } catch [SkipValue] {
                    continue
                }
                # Build current record
                $curRecord += $value.value
            }
        } catch [SkipRecord] {
            $this._clearRecord()
            return
        }

        # If no values in template or whole record is empty, don't output
        if ($curRecord.Count -eq 0 -or
            ($curRecord | Where-Object { $null -ne $_ -and (-not ($_ -is [array]) -or $_.Count -gt 0) }).Count -eq 0) {
            return
        }

        # Replace null entries with empty string
        for ($i = 0; $i -lt $curRecord.Count; $i++) {
            if ($null -eq $curRecord[$i]) {
                $curRecord[$i] = ''
            }
        }

        $this._result += ,$curRecord
        $this._clearRecord()
    }

    [void] _parse([string]$template) {
        if (-not $template) {
            throw [TextFSMTemplateError]::new('Null template.')
        }

        # Split template into lines, handling different line endings
        $lines = $template -replace "`r`n", "`n" -replace "`r", "`n" -split "`n"

        # Parse Variables section
        $lineIndex = $this._parseVariables($lines)

        # Parse States
        while ($lineIndex -lt $lines.Length) {
            $lineIndex = $this._parseState($lines, $lineIndex)
        }

        # Validate FSM
        $this._validateFSM()

        # Perform additional validations
        $this._validateConsistency()
    }

    [int] _parseVariables([string[]]$lines) {
        $this.values = @()
        $lineIndex = 0

        for (; $lineIndex -lt $lines.Length; $lineIndex++) {
            $this._lineNum = $lineIndex + 1
            $line = $lines[$lineIndex].Trim()

            # Blank line signifies end of Value definitions
            if (-not $line) {
                return $lineIndex + 1
            }

            # Skip commented lines
            if ($line.StartsWith('#')) {
                continue
            }

            if ($line.StartsWith('Value ')) {
                try {
                    $value = [TextFSMValue]::new(
                        $this,
                        $this.MAX_NAME_LEN,
                        $this._options_cls
                    )
                    $value.Parse($line)

                    $header = $this._getHeader()
                    if ($header -contains $value.name) {
                        throw [TextFSMTemplateError]::new(
                            "Duplicate declarations for Value '$($value.name)'. Line: $($this._lineNum)"
                        )
                    }

                    $this._validateOptions($value)
                    $this.values += $value
                    $this.valueMap[$value.name] = $value.template
                } catch [TextFSMTemplateError] {
                    throw [TextFSMTemplateError]::new("$($_.Exception.Message) Line $($this._lineNum).")
                } catch {
                    throw
                }
            } elseif ($this.values.Count -eq 0) {
                throw [TextFSMTemplateError]::new('No Value definitions found.')
            } else {
                throw [TextFSMTemplateError]::new(
                    "Expected blank line after last Value entry. Line: $($this._lineNum)."
                )
            }
        }

        return $lineIndex
    }


    [int] _parseState([string[]]$lines, [int]$startIndex) {
        $lineIndex = $startIndex
        $stateName = ''

        # Find state definition
        for (; $lineIndex -lt $lines.Length; $lineIndex++) {
            $this._lineNum = $lineIndex + 1
            $line = $lines[$lineIndex]
            $trimmedLine = $line.Trim()

            # Skip blank lines and comments
            if (-not $trimmedLine -or $trimmedLine.StartsWith('#')) {
                continue
            }

            # First non-blank, non-comment line is state definition
            $stateNameRe = '^(\w+)$'
            if (-not ($trimmedLine -match $stateNameRe) -or
                $trimmedLine.Length -gt $this.MAX_NAME_LEN -or
                [TextFSMRule]::LINE_OP -contains $trimmedLine -or
                [TextFSMRule]::RECORD_OP -contains $trimmedLine) {
                throw [TextFSMTemplateError]::new(
                    "Invalid state name: '$trimmedLine'. Line: $($this._lineNum)"
                )
            }

            $stateName = $trimmedLine
            if ($this.states.ContainsKey($stateName)) {
                throw [TextFSMTemplateError]::new(
                    "Duplicate state name: '$trimmedLine'. Line: $($this._lineNum)"
                )
            }

            $this.states[$stateName] = @()
            $this.stateList += $stateName
            $lineIndex++
            break
        }

        if (-not $stateName) {
            return $lines.Length # End of file
        }

        # Parse rules in this state
        for (; $lineIndex -lt $lines.Length; $lineIndex++) {
            $this._lineNum = $lineIndex + 1
            $line = $lines[$lineIndex]
            $trimmedLine = $line.Trim()

            # Blank line ends the state
            if (-not $trimmedLine) {
                return $lineIndex + 1
            }

            # Skip comments
            if ($trimmedLine.StartsWith('#')) {
                continue
            }

            # Check rule format
            $validPrefixes = @(' ^', '  ^', '\t^')
            $hasValidPrefix = $false
            foreach ($prefix in $validPrefixes) {
                if ($line.StartsWith($prefix)) {
                    $hasValidPrefix = $true
                    break
                }
            }

            if (-not $hasValidPrefix) {
                throw [TextFSMTemplateError]::new(
                    "Missing white space or carat ('^') before rule. Line: $($this._lineNum). Content: `"$line`""
                )
            }

            # Add rule to state
            $this.states[$stateName] += [TextFSMRule]::new($line, $this._lineNum, $this.valueMap)
        }

        return $lines.Length # End of file
    }

    [bool] _validateFSM() {
        # Must have 'Start' state
        if (-not $this.states.ContainsKey('Start')) {
            throw [TextFSMTemplateError]::new("Missing state 'Start'.")
        }

        # 'End' state (if specified) must be empty
        if ($this.states.ContainsKey('End') -and $this.states['End'].Count -gt 0) {
            throw [TextFSMTemplateError]::new("Non-Empty 'End' state.")
        }

        # Remove 'End' state
        if ($this.states.ContainsKey('End')) {
            $this.states.Remove('End')
            $this.stateList = $this.stateList | Where-Object { $_ -ne 'End' }
        }

        # Ensure jump states are all valid
        foreach ($state in $this.states.Keys) {
            foreach ($rule in $this.states[$state]) {
                if ($rule.lineOp -eq 'Error') {
                    continue
                }

                if (-not $rule.newState -or $rule.newState -eq 'End' -or $rule.newState -eq 'EOF') {
                    continue
                }

                if (-not $this.states.ContainsKey($rule.newState)) {
                    throw [TextFSMTemplateError]::new(
                        "State '$($rule.newState)' not found, referenced in state '$state'"
                    )
                }
            }
        }

        return $true
    }

    [bool] _validateConsistency() {
        # Check for undefined value references in rules
        foreach ($stateName in $this.states.Keys) {
            foreach ($rule in $this.states[$stateName]) {
                # Extract variable references from the rule pattern using regex
                $valueRefs = [regex]::Matches($rule.match, '\${(\w+)}') |
                    ForEach-Object { $_.Groups[1].Value }

                foreach ($ref in $valueRefs) {
                    if (-not $this.valueMap.ContainsKey($ref)) {
                        throw [TextFSMTemplateError]::new(
                            "Rule in state '$stateName' references undefined value '$ref'"
                        )
                    }
                }
            }
        }

        # Validate regex patterns in values are valid
        foreach ($value in $this.values) {
            try {
                if ($null -eq $value.compiledRegex) {
                    throw [System.Exception]::new("Value '$($value.name)' has no compiled regex")
                }
                # Test the regex with a simple string to verify it compiles
                [void]$value.compiledRegex.IsMatch("")
            } catch {
                throw [TextFSMTemplateError]::new(
                    "Invalid regex in value '$($value.name)': $($_.Exception.Message)"
                )
            }
        }

        # Check for unreachable states
        $reachableStates = [System.Collections.Generic.HashSet[string]]::new()
        [void]$reachableStates.Add('Start')
        $statesAdded = $true

        # Keep adding states until no new states are found
        while ($statesAdded) {
            $statesAdded = $false
            $currentStates = $reachableStates.ToArray()

            foreach ($stateName in $currentStates) {
                if (-not $this.states.ContainsKey($stateName)) { continue }

                foreach ($rule in $this.states[$stateName]) {
                    if ($rule.newState -and
                        $rule.newState -ne 'End' -and
                        $rule.newState -ne 'EOF' -and
                        -not $reachableStates.Contains($rule.newState)) {
                        [void]$reachableStates.Add($rule.newState)
                        $statesAdded = $true
                    }
                }
            }
        }

        # Find unreachable states
        $unreachableStates = $this.stateList | Where-Object {
            $_ -ne 'End' -and $_ -ne 'EOF' -and -not $reachableStates.Contains($_)
        }

        if ($unreachableStates.Count -gt 0) {
            throw [TextFSMTemplateError]::new(
                "Unreachable states found: $($unreachableStates -join ', ')"
            )
        }

        # Validate option combinations
        foreach ($value in $this.values) {
            $options = $value.OptionNames()

            # Cannot have both Key and List
            if ($options -contains 'Key' -and $options -contains 'List') {
                throw [TextFSMTemplateError]::new(
                    "Value cannot have both 'Key' and 'List' options: '$($value.name)'"
                )
            }

            # Cannot have both Filldown and Fillup
            if ($options -contains 'Filldown' -and $options -contains 'Fillup') {
                throw [TextFSMTemplateError]::new(
                    "Value cannot have both 'Filldown' and 'Fillup' options: '$($value.name)'"
                )
            }

            # Warning for Required + Filldown combination
            if ($options -contains 'Required' -and $options -contains 'Filldown') {
                Write-Warning "Value '$($value.name)' has both 'Required' and 'Filldown' options, which may cause unexpected behavior"
            }
        }

        return $true
    }

    [void] _validateOptions([TextFSMValue]$value) {
        # Check for incompatible options
        $options = $value.OptionNames()

        # Cannot have both Key and List
        if ($options -contains 'Key' -and $options -contains 'List') {
            throw [TextFSMTemplateError]::new(
                "Value cannot have both 'Key' and 'List' options: '$($value.name)'"
            )
        }

        # Cannot have both Filldown and Fillup
        if ($options -contains 'Filldown' -and $options -contains 'Fillup') {
            throw [TextFSMTemplateError]::new(
                "Value cannot have both 'Filldown' and 'Fillup' options: '$($value.name)'"
            )
        }

        # Additional validation can be added here
    }

    [array] parseText([string]$text, [bool]$eof = $true) {
        if (-not $text) {
            return $this._result
        }

        # Normalize line endings
        $lines = $text -replace "`r`n", "`n" -replace "`r", "`n" -split "`n"

        # Process each line
        foreach ($line in $lines) {
            $this._processLine($line)
            if ($this._curStateName -eq 'End') {
                break
            }
        }

        # Handle EOF state if it exists
        if ($this._curStateName -ne 'End' -and $eof) {
            if ($this.states.ContainsKey('EOF')) {
                # Process rules in the EOF state
                $this._curState = $this.states['EOF']
                $this._curStateName = 'EOF'
                $this._processLine('') # Process with empty line to trigger EOF rules
            } else {
                # No EOF state defined, just append the current record
                $this._appendRecord()
            }
        }

        return $this._result
    }

    [void] _processLine([string]$line) {
        # Pre-process the line before checking rules
        $trimmedLine = $this._preprocessLine($line)
        $this._checkLine($trimmedLine)
    }

    [string] _preprocessLine([string]$line) {
        # Remove trailing whitespace
        # This better matches Python's behavior when handling lines
        return $line -replace '\s+$', ''
    }

    [void] _checkLine([string]$line) {
        foreach ($rule in $this._curState) {
            $matched = $this._checkRule($rule, $line)
            if ($matched) {
                # Process captured groups
                foreach ($groupName in $matched.Groups.Keys | Where-Object { $_ -match '^\w+$' }) {
                    $this._assignVar($matched, $groupName)
                }

                if ($this._operations($rule, $line)) {
                    # Not a Continue, so check for state transition
                    if ($rule.newState) {
                        if ($rule.newState -ne 'End' -and $rule.newState -ne 'EOF') {
                            $this._curState = $this.states[$rule.newState]
                        }
                        $this._curStateName = $rule.newState
                    }
                    break
                }
            }
        }
    }

    [System.Text.RegularExpressions.Match] _checkRule([TextFSMRule]$rule, [string]$line) {
        # This is a separate method so it can be overridden for debugging
        return $rule.regexObj.Match($line)
    }

    [void] _assignVar([System.Text.RegularExpressions.Match]$matched, [string]$value) {
        $fsm_value = $this._getValue($value)
        if ($fsm_value) {
            # If we have a matched group, use it
            if ($matched.Groups[$value] -and $matched.Groups[$value].Success) {
                $fsm_value.AssignVar($matched.Groups[$value].Value)
            }
        }
    }

    [bool] _operations([TextFSMRule]$rule, [string]$line) {
        # Process record operators
        if ($rule.recordOp -eq 'Record') {
            $this._appendRecord()
        } elseif ($rule.recordOp -eq 'Clear') {
            $this._clearRecord()
        } elseif ($rule.recordOp -eq 'Clearall') {
            $this._clearAllRecord()
        }

        # Process line operators
        if ($rule.lineOp -eq 'Error') {
            if ($rule.newState) {
                throw [TextFSMError]::new(
                    "Error: $($rule.newState). Rule Line: $($rule.lineNum). Input Line: $line."
                )
            }
            throw [TextFSMError]::new(
                "State Error raised. Rule Line: $($rule.lineNum). Input Line: $line."
            )
        } elseif ($rule.lineOp -eq 'Continue') {
            # Continue with current line
            return $false
        }

        # Return to start of current state with new line
        return $true
    }

    [void] _clearRecord() {
        # Remove non-Filldown record entries
        foreach ($value in $this.values) {
            $value.ClearVar()
        }
    }

    [void] _clearAllRecord() {
        # Remove all record entries
        foreach ($value in $this.values) {
            $value.ClearAllVar()
        }
    }

    [array] parseTextToDicts([string]$text, [bool]$eof = $true) {
        $resultLists = $this.parseText($text, $eof)
        $resultDicts = @()

        foreach ($row in $resultLists) {
            $dict = [ordered]@{}
            for ($i = 0; $i -lt $this.header().Count; $i++) {
                # Use the header value as the property name
                $headerName = $this.header()[$i]
                $dict[$headerName] = $row[$i]
            }
            $resultDicts += [PSCustomObject]$dict
        }

        return $resultDicts
    }

    [string[]] getValuesByAttrib([string]$attribute) {
        if (-not ($this._options_cls::ValidOptions() -contains $attribute)) {
            throw [System.ArgumentException]::new("'$attribute': Not a valid attribute.")
        }

        return $this.values |
            Where-Object { $_.OptionNames() -contains $attribute } |
            ForEach-Object { $_.name }
    }

    [string] ToString() {
        $result = $this.values | ForEach-Object { $_.ToString() } | Join-String -Separator "`n"
        $result += "`n"

        foreach ($state in $this.stateList) {
            $result += "`n$state`n"
            if ($this.states[$state].Count) {
                $result += ($this.states[$state] | ForEach-Object { $_.ToString() } | Join-String -Separator "`n") + "`n"
            }
        }

        return $result
    }
}
#endregion

#region Public Functions
function New-TextFSMParser {
    <#
    .SYNOPSIS
        Creates a new TextFSM parser from a template.
    .DESCRIPTION
        Creates a new TextFSM parser using the specified template file or content.
    .PARAMETER Path
        Path to a TextFSM template file.
    .PARAMETER Content
        Raw content of a TextFSM template.
    .EXAMPLE
        $parser = New-TextFSMParser -Path "templates/cisco_ios_show_version.textfsm"
    .EXAMPLE
        $template = Get-Content -Path "templates/cisco_ios_show_version.textfsm" -Raw
        $parser = New-TextFSMParser -Content $template
    .NOTES
        This function creates a TextFSM parser that can be used with the ConvertFrom-TextFSM function.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([TextFSM])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]$Content
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $Content = Get-Content -Path $Path -Raw -ErrorAction Stop
        }

        return [TextFSM]::new($Content)
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function ConvertFrom-TextFSM {
    <#
    .SYNOPSIS
        Parses text using a TextFSM parser.
    .DESCRIPTION
        Parses the input text using the specified TextFSM parser and returns the results.
    .PARAMETER InputObject
        Input text to parse.
    .PARAMETER Parser
        TextFSM parser to use.
    .PARAMETER Path
        Path to a TextFSM template file. Alternative to specifying a Parser.
    .PARAMETER AsDictionary
        Return results as dictionary objects rather than lists.
    .PARAMETER NoEOF
        Do not process EOF state in the template.
    .EXAMPLE
        $results = Get-Content -Path "device_output.txt" -Raw | ConvertFrom-TextFSM -Parser $parser
    .EXAMPLE
        $results = ConvertFrom-TextFSM -InputObject $deviceOutput -Path "templates/cisco_ios_show_version.textfsm" -AsDictionary
    .NOTES
        This function parses text using a TextFSM parser and returns the results.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Parser')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'Parser')]
        [TextFSM]$Parser,

        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter()]
        [switch]$AsDictionary,

        [Parameter()]
        [switch]$NoEOF
    )

    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $Parser = New-TextFSMParser -Path $Path
            }

            $eof = -not $NoEOF

            if ($AsDictionary) {
                return $Parser.parseTextToDicts($InputObject, $eof)
            } else {
                return $Parser.parseText($InputObject, $eof)
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'New-TextFSMParser',
    'ConvertFrom-TextFSM'
)
#endregion