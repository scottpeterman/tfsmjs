# Example demonstrating the TextFSM PowerShell module with a more complex template

# Import the TextFSM module (assuming it's saved as TextFSM.psm1)
# Import-Module ./TextFSM.psm1

# Sample template for parsing Cisco IOS show ip bgp neighbors output
$templateContent = @"
Value Filldown ROUTER_ID (\d+\.\d+\.\d+\.\d+)
Value Filldown LOCAL_AS (\d+)
Value Required BGP_NEIGH (\d+\.\d+\.\d+\.\d+)
Value NEIGH_AS (\d+)
Value BGP_STATE (\w+)
Value UPTIME (.*)
Value LAST_READ (.*)
Value LAST_WRITE (.*)
Value RECEIVED (\d+)
Value SENT (\d+)
Value RCV_QUEUE (\d+)
Value SND_QUEUE (\d+)
Value TOTAL_RECEIVED (\d+)
Value TOTAL_SENT (\d+)
Value IN_PFXS (\d+)

Start
  ^BGP router identifier ${ROUTER_ID}, local AS number ${LOCAL_AS}\s*$$
  ^Neighbor\s+V\s+AS\s+MsgRcvd\s+MsgSent\s+TblVer\s+InQ\s+OutQ\s+Up/Down\s+State/PfxRcd\s*$$ -> Neighbor_Table
  ^.+ -> Continue.Record
  ^. -> Error

Neighbor_Table
  ^${BGP_NEIGH}\s+\d+\s+${NEIGH_AS}\s+${RECEIVED}\s+${SENT}\s+\d+\s+${RCV_QUEUE}\s+${SND_QUEUE}\s+${UPTIME}\s+(${BGP_STATE}|\d+) -> Continue.Record
  ^\s*$$ -> BGP_Neighbor_Detail
  ^. -> Error

BGP_Neighbor_Detail
  ^BGP neighbor is ${BGP_NEIGH},\s+remote AS ${NEIGH_AS},.*$$ -> Continue.Record
  ^\s+BGP state = ${BGP_STATE},.*$$
  ^\s+Last read ${LAST_READ},.*$$
  ^\s+Last write ${LAST_WRITE},.*$$
  ^\s+Total: path\s+Prefix\s+SID\s+neighbor\s*$$
  ^\s+(\w+\s+){1,5}${IN_PFXS}(\s+\w+)*\s*$$
  ^\s+Connections established ${TOTAL_RECEIVED}, dropped ${TOTAL_SENT}\s*$$
  ^.+ -> Continue.Record
  ^\s*$$ -> Start
  ^. -> Error
"@

# Sample device output
$deviceOutput = @"
BGP router identifier 192.168.1.1, local AS number 65001
BGP table version is 8, main routing table version 8
2 network entries using 288 bytes of memory
2 path entries using 160 bytes of memory
2/1 BGP path/bestpath attribute entries using 304 bytes of memory
1 BGP AS-PATH entries using 24 bytes of memory
0 BGP route-map cache entries using 0 bytes of memory
0 BGP filter-list cache entries using 0 bytes of memory
BGP using 776 total bytes of memory
BGP activity 4/2 prefixes, 4/2 paths, scan interval 60 secs

Neighbor        V    AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
10.1.1.2        4 65002    5467    5472        8    0    0 3d21h    2
10.2.2.2        4 65003   10251   10246        8    0    0 5d10h    1

BGP neighbor is 10.1.1.2,  remote AS 65002, external link
  BGP version 4, remote router ID 192.168.2.2
  BGP state = Established, up for 3d21h
  Last read 00:00:16, Last write 00:00:21
  Hold time is 180, keepalive interval is 60 seconds
  Neighbor capabilities:
    Route refresh: advertised and received(new)
    Four-octets ASN Capability: advertised and received
    Address family IPv4 Unicast: advertised and received
  Message statistics:
    InQ depth is 0
    OutQ depth is 0
                         Sent       Rcvd
    Opens:                  1          1
    Notifications:          0          0
    Updates:              143          6
    Keepalives:          5328       5460
    Route Refresh:          0          0
    Total:               5472       5467
  Default minimum time between advertisement runs is 30 seconds
  Connections established 1, dropped 0
  Last reset never
  Transport(tcp) path-mtu-discovery is enabled
  Graceful-Restart is disabled
 For address family: IPv4 Unicast
  BGP table version 8, neighbor version 8
  Index 1, Offset 0, Mask 0x2
  2 accepted prefixes
  0 denied prefixes
  0 withdrawn prefixes

BGP neighbor is 10.2.2.2,  remote AS 65003, external link
  BGP version 4, remote router ID 192.168.3.3
  BGP state = Established, up for 5d10h
  Last read 00:00:50, Last write 00:00:13
  Hold time is 180, keepalive interval is 60 seconds
  Neighbor capabilities:
    Route refresh: advertised and received(new)
    Four-octets ASN Capability: advertised and received
    Address family IPv4 Unicast: advertised and received
  Message statistics:
    InQ depth is 0
    OutQ depth is 0
                         Sent       Rcvd
    Opens:                  2          2
    Notifications:          1          0
    Updates:              145          9
    Keepalives:         10098      10240
    Route Refresh:          0          0
    Total:              10246      10251
  Default minimum time between advertisement runs is 30 seconds
  Connections established 2, dropped 1
  Last reset 5d10h, due to BGP Notification sent
  Transport(tcp) path-mtu-discovery is enabled
  Graceful-Restart is disabled
 For address family: IPv4 Unicast
  BGP table version 8, neighbor version 8
  Index 2, Offset 0, Mask 0x4
  1 accepted prefixes
  0 denied prefixes
  0 withdrawn prefixes
"@

# Function to demonstrate TextFSM parsing with a complex template
function Test-ComplexTextFSM {
    param (
        [string]$Template,
        [string]$InputText
    )

    try {
        # Create the parser
        Write-Host "Creating TextFSM parser..." -ForegroundColor Cyan
        $fsm = [TextFSM]::new($Template)

        Write-Host "Parser created successfully with the following values:" -ForegroundColor Green
        foreach ($value in $fsm.values) {
            $options = if ($value.options.Count -gt 0) {
                " [" + ($value.options.name -join ", ") + "]"
            } else {
                ""
            }
            Write-Host "  - $($value.name)$options" -ForegroundColor Yellow
        }

        # Parse the input text
        Write-Host "`nParsing input text..." -ForegroundColor Cyan
        $result = $fsm.parseText($InputText)

        Write-Host "Parsing successful!" -ForegroundColor Green
        Write-Host "Parsed $($result.Count) records" -ForegroundColor Yellow

        # Display the header
        Write-Host "`nHeader: $($fsm.header() -join ', ')" -ForegroundColor Cyan

        # Convert to dictionaries for easier display
        $dictResults = $fsm.parseTextToDicts($InputText)

        # Display results in a more readable format
        Write-Host "`nResults:" -ForegroundColor Cyan
        foreach ($entry in $dictResults) {
            Write-Host "`n===== BGP Neighbor: $($entry.BGP_NEIGH) =====" -ForegroundColor Green

            # Create a formatted output
            $props = [ordered]@{
                "Router ID" = $entry.ROUTER_ID
                "Local AS" = $entry.LOCAL_AS
                "Neighbor AS" = $entry.NEIGH_AS
                "BGP State" = $entry.BGP_STATE
                "Uptime" = $entry.UPTIME
                "Last Read" = $entry.LAST_READ
                "Last Write" = $entry.LAST_WRITE
                "Messages Received" = $entry.RECEIVED
                "Messages Sent" = $entry.SENT
                "Receive Queue" = $entry.RCV_QUEUE
                "Send Queue" = $entry.SND_QUEUE
                "Total Connections Established" = $entry.TOTAL_RECEIVED
                "Total Connections Dropped" = $entry.TOTAL_SENT
                "Prefixes Received" = $entry.IN_PFXS
            }

            [PSCustomObject]$props | Format-List
        }

        # Analysis example
        Write-Host "`nAnalysis Example:" -ForegroundColor Cyan

        $totalMessages = ($dictResults | Measure-Object -Property RECEIVED -Sum).Sum +
                        ($dictResults | Measure-Object -Property SENT -Sum).Sum

        Write-Host "Total BGP messages exchanged: $totalMessages" -ForegroundColor Yellow

        $neighborsPerAS = $dictResults | Group-Object -Property NEIGH_AS | Sort-Object -Property Count -Descending
        Write-Host "BGP Neighbors per AS:" -ForegroundColor Yellow
        foreach ($asGroup in $neighborsPerAS) {
            Write-Host "  AS $($asGroup.Name): $($asGroup.Count) neighbor(s)" -ForegroundColor White
        }

        $totalPrefixes = ($dictResults | Measure-Object -Property IN_PFXS -Sum).Sum
        Write-Host "Total prefixes received: $totalPrefixes" -ForegroundColor Yellow

        return $dictResults
    }
    catch {
        Write-Error "Error: $_"
        Write-Host "Exception details:" -ForegroundColor Red
        $_.Exception | Format-List -Force
        return $null
    }
}

# Run the test
$results = Test-ComplexTextFSM -Template $templateContent -InputText $deviceOutput

# Example of exporting to CSV
if ($results) {
    Write-Host "`nExporting to CSV..." -ForegroundColor Cyan
    $csvPath = "bgp_neighbors.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Exported to $csvPath" -ForegroundColor Green

    # Optional: Convert to JSON
    $jsonPath = "bgp_neighbors.json"
    $results | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonPath
    Write-Host "Exported to $jsonPath" -ForegroundColor Green
}

# Example of how to compare neighbor states
if ($results) {
    Write-Host "`nBGP Neighbor State Analysis:" -ForegroundColor Cyan

    $establishedNeighbors = $results | Where-Object { $_.BGP_STATE -eq 'Established' }
    $nonEstablishedNeighbors = $results | Where-Object { $_.BGP_STATE -ne 'Established' }

    Write-Host "Established BGP Sessions: $($establishedNeighbors.Count)" -ForegroundColor Green

    if ($nonEstablishedNeighbors.Count -gt 0) {
        Write-Host "Non-Established BGP Sessions: $($nonEstablishedNeighbors.Count)" -ForegroundColor Red
        foreach ($neighbor in $nonEstablishedNeighbors) {
            Write-Host "  - $($neighbor.BGP_NEIGH) (AS $($neighbor.NEIGH_AS)): $($neighbor.BGP_STATE)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "All BGP sessions are established." -ForegroundColor Green
    }

    # Check for potential connection issues
    $droppedConnections = $results | Where-Object { [int]$_.TOTAL_SENT -gt 0 }
    if ($droppedConnections.Count -gt 0) {
        Write-Host "`nNeighbors with Dropped Connections:" -ForegroundColor Yellow
        foreach ($neighbor in $droppedConnections) {
            Write-Host "  - $($neighbor.BGP_NEIGH): $($neighbor.TOTAL_SENT) dropped connection(s)" -ForegroundColor Yellow
        }
    }
}

# Example of using a function to process multiple files with TextFSM
function Process-DeviceOutputsWithTextFSM {
    <#
    .SYNOPSIS
        Processes multiple device output files using a specified TextFSM template.
    .DESCRIPTION
        This function takes a directory of device output files and processes each file
        using the specified TextFSM template. Results are combined and returned.
    .PARAMETER TemplateFile
        Path to the TextFSM template file.
    .PARAMETER DeviceOutputDirectory
        Directory containing device output files.
    .PARAMETER FilePattern
        File pattern to match device output files (default: *.txt).
    .PARAMETER OutputCSV
        Path to save combined results as CSV (optional).
    .EXAMPLE
        Process-DeviceOutputsWithTextFSM -TemplateFile "templates/cisco_ios_show_ip_bgp_neighbors.textfsm" -DeviceOutputDirectory "device_outputs" -OutputCSV "combined_results.csv"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TemplateFile,

        [Parameter(Mandatory = $true)]
        [string]$DeviceOutputDirectory,

        [Parameter()]
        [string]$FilePattern = "*.txt",

        [Parameter()]
        [string]$OutputCSV
    )

    try {
        # Create parser once
        $parser = [TextFSM]::new((Get-Content -Path $TemplateFile -Raw))
        Write-Host "Created TextFSM parser using template: $TemplateFile" -ForegroundColor Cyan

        # Get all matching files
        $files = Get-ChildItem -Path $DeviceOutputDirectory -Filter $FilePattern
        Write-Host "Found $($files.Count) files matching pattern '$FilePattern'" -ForegroundColor Cyan

        $allResults = @()
        $deviceCount = 0

        # Process each file
        foreach ($file in $files) {
            Write-Host "Processing file: $($file.Name)" -ForegroundColor Yellow
            $content = Get-Content -Path $file.FullName -Raw

            # Add device information to results
            $deviceResults = $parser.parseTextToDicts($content)

            # Add file name as source
            foreach ($result in $deviceResults) {
                Add-Member -InputObject $result -MemberType NoteProperty -Name "SourceDevice" -Value $file.BaseName
            }

            $allResults += $deviceResults
            $deviceCount++

            Write-Host "  - Processed $($deviceResults.Count) records" -ForegroundColor Green
        }

        Write-Host "`nProcessed $deviceCount devices with $($allResults.Count) total records" -ForegroundColor Green

        # Export to CSV if requested
        if ($OutputCSV) {
            $allResults | Export-Csv -Path $OutputCSV -NoTypeInformation
            Write-Host "Exported combined results to $OutputCSV" -ForegroundColor Green
        }

        return $allResults
    }
    catch {
        Write-Error "Error processing files: $_"
        return $null
    }
}

# Example usage of multi-file processing (commented out as it requires actual files)
<#
$multiDeviceResults = Process-DeviceOutputsWithTextFSM -TemplateFile "templates/cisco_ios_show_ip_bgp_neighbors.textfsm" `
                                                     -DeviceOutputDirectory "device_outputs" `
                                                     -OutputCSV "all_bgp_neighbors.csv"
#>

# Show an example of how to extend the TextFSM class for custom functionality
Write-Host "`nExtending TextFSM with Custom Functionality" -ForegroundColor Cyan

# Example of a custom TextFSM class with additional functionality
class ExtendedTextFSM : TextFSM {
    [hashtable]$_statistics = @{}

    ExtendedTextFSM([string]$template) : base($template) {
        # Constructor inherits from base class
    }

    # Add a custom method to calculate statistics
    [hashtable] CalculateStatistics([string]$inputText) {
        $results = $this.parseTextToDicts($inputText)
        $stats = @{
            TotalRecords = $results.Count
            UniqueValues = @{}
            Averages = @{}
            Maximums = @{}
            Minimums = @{}
        }

        # Get all numeric fields
        $numericFields = @()
        foreach ($header in $this.header()) {
            $sample = $results[0].$header
            if ($sample -match '^\d+) {
                $numericFields += $header
            }
        }

        # Calculate statistics for each field
        foreach ($field in $this.header()) {
            # Count unique values for all fields
            $uniqueValues = $results.$field | Select-Object -Unique
            $stats.UniqueValues[$field] = @{
                Count = $uniqueValues.Count
                Values = $uniqueValues
            }

            # Calculate statistics for numeric fields
            if ($numericFields -contains $field) {
                # Convert string values to integers for calculation
                $numericValues = $results.$field | ForEach-Object { [int]$_ }

                if ($numericValues.Count -gt 0) {
                    $stats.Averages[$field] = ($numericValues | Measure-Object -Average).Average
                    $stats.Maximums[$field] = ($numericValues | Measure-Object -Maximum).Maximum
                    $stats.Minimums[$field] = ($numericValues | Measure-Object -Minimum).Minimum
                }
            }
        }

        $this._statistics = $stats
        return $stats
    }

    # Generate a summary report
    [string] GenerateReport([string]$inputText) {
        if ($this._statistics.Count -eq 0) {
            $this.CalculateStatistics($inputText)
        }

        $report = "TextFSM Parsing Report`n"
        $report += "=====================`n`n"

        $report += "Total Records: $($this._statistics.TotalRecords)`n"
        $report += "Fields: $($this.header() -join ', ')`n`n"

        $report += "Statistical Summary:`n"
        $report += "------------------`n"

        foreach ($field in $this._statistics.Averages.Keys) {
            $report += "Field: $field`n"
            $report += "  - Average: $($this._statistics.Averages[$field])`n"
            $report += "  - Maximum: $($this._statistics.Maximums[$field])`n"
            $report += "  - Minimum: $($this._statistics.Minimums[$field])`n"
            $report += "  - Unique Values: $($this._statistics.UniqueValues[$field].Count)`n`n"
        }

        return $report
    }
}

# Demonstrate the extended class
try {
    Write-Host "Creating Extended TextFSM parser..." -ForegroundColor Yellow
    $extendedFsm = [ExtendedTextFSM]::new($templateContent)

    Write-Host "Calculating statistics..." -ForegroundColor Yellow
    $stats = $extendedFsm.CalculateStatistics($deviceOutput)

    Write-Host "Statistics calculated:" -ForegroundColor Green
    Write-Host "  - Total Records: $($stats.TotalRecords)" -ForegroundColor White

    Write-Host "  - Numeric field averages:" -ForegroundColor White
    foreach ($field in $stats.Averages.Keys) {
        Write-Host "    - $field : $($stats.Averages[$field])" -ForegroundColor White
    }

    Write-Host "`nGenerating report..." -ForegroundColor Yellow
    $report = $extendedFsm.GenerateReport($deviceOutput)

    # Write report to file
    $reportPath = "bgp_analysis_report.txt"
    $report | Out-File -FilePath $reportPath
    Write-Host "Report written to $reportPath" -ForegroundColor Green

    # Display part of the report
    Write-Host "`nReport Preview:" -ForegroundColor Cyan
    Write-Host ($report -split "`n" | Select-Object -First 15) -ForegroundColor White
}
catch {
    Write-Error "Error with extended TextFSM: $_"
}

Write-Host "`nTextFSM PowerShell Implementation Demo Completed" -ForegroundColor Cyan