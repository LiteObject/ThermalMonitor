# Chrome Tab Monitor - Real-time Chrome Process Analysis
# Run this alongside ThermalMonitor.ps1 to identify problematic Chrome tabs
# Requirements: Run as Administrator for full process access

param(
    [ValidateRange(1, 300)]
    [int]$RefreshInterval = 5,   # Refresh every N seconds (1-300 seconds allowed)
    [int]$TopProcessCount = 10,   # Show top N processes
    [switch]$ShowAll = $false,    # Show all Chrome processes instead of just top ones
    [int]$HighCpuThreshold = 1,   # CPU % threshold for highlighting
    [int]$HighMemoryThreshold = 100, # Memory (MB) threshold for highlighting
    [switch]$ExportToCsv = $false,
    [string]$ExportPath = $(Join-Path -Path (Get-Location) -ChildPath ("ChromeAnalysis_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".csv"))
)

# Function to get Chrome process type from command line
function Get-ChromeProcessType {
    param($CommandLine)
    
    $result = [PSCustomObject]@{ Type = "Main"; Detail = "" }
    if (-not $CommandLine) { return $result }
    
    if ($CommandLine -match "--type=renderer") {
        if ($CommandLine -match "--extension-process") {
            $result.Type = "Extension"
            if ($CommandLine -match "\\Extensions\\([^\\]+)") { $result.Detail = "Ext ID: " + $matches[1] }
        } elseif ($CommandLine -match "--app=([^\s]+)") {
            $result.Type = "App"; $result.Detail = $matches[1]
        } else {
            $result.Type = "Tab"
            if ($CommandLine -match "--origin-trial-public-key=") { $result.Detail = "Site-isolated" }
        }
    } elseif ($CommandLine -match "--type=gpu-process") {
        $result.Type = "GPU"
    } elseif ($CommandLine -match "--type=utility") {
        if ($CommandLine -match "audio") { $result.Type = "Audio Service" }
        elseif ($CommandLine -match "network") { $result.Type = "Network Service" }
        elseif ($CommandLine -match "storage") { $result.Type = "Storage Service" }
        else { $result.Type = "Utility" }
    } elseif ($CommandLine -match "--type=browser") {
        $result.Type = "Browser Main"
    } elseif ($CommandLine -match "--type=crashpad") {
        $result.Type = "Crash Handler"
    } elseif ($CommandLine -match "--type=zygote") {
        $result.Type = "Zygote"
    }
    return $result
}

# Function to estimate CPU usage
function Get-ProcessCpuUsage {
    param($Process)
    
    # Fallback time-based estimate if perf counters unavailable
    try {
        if (-not $Process.CPU) { return 0 }
        $cpuTime = $Process.TotalProcessorTime.TotalSeconds
        $runTime = (Get-Date) - $Process.StartTime
        if ($runTime.TotalSeconds -gt 1) {
            $cpuPercent = ($cpuTime / $runTime.TotalSeconds) * 100 / [Environment]::ProcessorCount
            return [math]::Round([math]::Min($cpuPercent, 100), 2)
        }
    } catch { }
    return 0
}

# Build a snapshot of CPU % per PID using performance counters
function Get-PerfCpuSnapshot {
    try {
        $counters = Get-Counter -Counter "\Process(*)\% Processor Time","\Process(*)\ID Process" -ErrorAction Stop
        $cpuMap = @{}
        $pidByInstance = @{}
        foreach ($s in $counters.CounterSamples) {
            if ($s.Path -like "*% Processor Time") {
                $cpuMap[$s.InstanceName] = $s.CookedValue
            } elseif ($s.Path -like "*ID Process") {
                $pidByInstance[$s.InstanceName] = [int]$s.CookedValue
            }
        }
        # Aggregate by PID (some processes have multiple instances like chrome, chrome#1, etc.)
        $pidCpu = @{}
        $cpuCount = [Environment]::ProcessorCount
        foreach ($instance in $cpuMap.Keys) {
            if ($pidByInstance.ContainsKey($instance)) {
                $processId = $pidByInstance[$instance]
                $val = [math]::Round(($cpuMap[$instance] / $cpuCount), 2)
                if ($pidCpu.ContainsKey($processId)) { $pidCpu[$processId] += $val } else { $pidCpu[$processId] = $val }
            }
        }
        return $pidCpu
    } catch {
        return @{}
    }
}

# Function to format file size
function Format-FileSize {
    param($Bytes)
    
    if ($Bytes -ge 1GB) {
        return "$([math]::Round($Bytes / 1GB, 1)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([math]::Round($Bytes / 1MB, 0)) MB"
    } elseif ($Bytes -ge 1KB) {
        return "$([math]::Round($Bytes / 1KB, 0)) KB"
    } else {
        return "$Bytes B"
    }
}

# Function to get Chrome process details
function Get-ChromeProcessDetails {
    try {
        $chromeProcesses = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
        if (-not $chromeProcesses) { return $null }

        # Batch WMI/CIM query for performance
        $wmiProcesses = Get-CimInstance -Query "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='chrome.exe'" -ErrorAction SilentlyContinue
        $wmiByPid = @{}
        foreach ($w in ($wmiProcesses | Where-Object { $_ })) { $wmiByPid[[int]$w.ProcessId] = $w }

        # Snapshot CPU usage by PID using perf counters
        $pidCpu = Get-PerfCpuSnapshot

        $chromeDetails = @()
        $totalChromeProcesses = $chromeProcesses.Count
        $processedCount = 0
        Write-Progress -Activity "Analyzing Chrome Processes" -Status "Starting..." -PercentComplete 0

        foreach ($proc in $chromeProcesses) {
            $processedCount++
            $percentComplete = ($processedCount / $totalChromeProcesses) * 100
            Write-Progress -Activity "Analyzing Chrome Processes" -Status "Processing PID $($proc.Id)" -PercentComplete $percentComplete
            
            try {
                $processId = [int]$proc.Id
                $wmiProc = if ($wmiByPid.ContainsKey($processId)) { $wmiByPid[$processId] } else { $null }
                $commandLine = if ($wmiProc) { $wmiProc.CommandLine } else { "" }

                $typeInfo = Get-ChromeProcessType -CommandLine $commandLine
                $cpuUsage = if ($pidCpu.ContainsKey($processId)) { $pidCpu[$processId] } else { Get-ProcessCpuUsage -Process $proc }

                # Runtime formatting
                $runtime = if ($proc.StartTime) { (Get-Date) - $proc.StartTime } else { New-TimeSpan }
                $runtimeText = if ($runtime.TotalHours -ge 1) {
                    "$([math]::Floor($runtime.TotalHours)):$($runtime.Minutes.ToString('00')):$($runtime.Seconds.ToString('00'))"
                } else {
                    "$($runtime.Minutes):$($runtime.Seconds.ToString('00'))"
                }

                $chromeDetails += [PSCustomObject]@{
                    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    PID = $processId
                    Type = $typeInfo.Type
                    Info = $typeInfo.Detail
                    'CPU%' = $cpuUsage
                    'Memory' = Format-FileSize $proc.WorkingSet64
                    MemoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                    'Peak Memory' = Format-FileSize $proc.PeakWorkingSet64
                    Threads = $proc.Threads.Count
                    Handles = $proc.HandleCount
                    Runtime = $runtimeText
                    'Start Time' = if ($proc.StartTime) { $proc.StartTime.ToString("HH:mm:ss") } else { "Unknown" }
                    'Command Preview' = if ($commandLine.Length -gt 120) { $commandLine.Substring(0, 117) + "..." } else { $commandLine }
                }
            } catch [System.UnauthorizedAccessException] {
                $chromeDetails += [PSCustomObject]@{
                    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    PID = $proc.Id
                    Type = "Unknown (No Access)"
                    Info = ""
                    'CPU%' = 0
                    'Memory' = Format-FileSize $proc.WorkingSet64
                    MemoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                    'Peak Memory' = Format-FileSize $proc.PeakWorkingSet64
                    Threads = $proc.Threads.Count
                    Handles = $proc.HandleCount
                    Runtime = ""
                    'Start Time' = ""
                    'Command Preview' = ""
                }
            } catch {
                Write-Verbose "Could not access process PID $($proc.Id): $_"
            }
        }

        Write-Progress -Activity "Analyzing Chrome Processes" -Completed
        return $chromeDetails | Sort-Object 'CPU%' -Descending
    } catch {
        Write-Error "Error getting Chrome process details: $_"
        return $null
    }
}

# Main monitoring loop
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "              CHROME TAB MONITOR - Real-time Analysis" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host ""
Write-Host "Purpose: Identify which Chrome tabs and processes are consuming CPU/Memory" -ForegroundColor Yellow
Write-Host ""
Write-Host "Instructions:" -ForegroundColor Cyan
Write-Host "  1. Keep this window open alongside Thermal Monitor" -ForegroundColor White
Write-Host "  2. When Chrome shows high CPU usage, check the PIDs below" -ForegroundColor White
Write-Host "  3. Open Chrome Task Manager (Shift+Esc in Chrome) to match PIDs with tabs" -ForegroundColor White
Write-Host "  4. Use chrome://system/ for detailed Chrome internals" -ForegroundColor White
Write-Host ""
Write-Host "Refresh Interval: $RefreshInterval seconds | Top Processes: $TopProcessCount" -ForegroundColor Gray
Write-Host "CPU Threshold: $HighCpuThreshold% | Memory Threshold: $HighMemoryThreshold MB" -ForegroundColor Gray
Write-Host "Press Ctrl+C to exit" -ForegroundColor Gray
Write-Host ""

$iteration = 0

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    # Periodic GC to keep memory use stable for long sessions
    if ($iteration % 100 -eq 0) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
    
    # Clear screen and show header
    if ($iteration -gt 1) { Clear-Host }
    
    Write-Host "Chrome Process Monitor - $timestamp (Iteration: $iteration)" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    
    try {
        $chromeData = Get-ChromeProcessDetails
        
        if ($chromeData) {
            $totalProcesses = $chromeData.Count
            $totalMemoryMB = [math]::Round(($chromeData | Measure-Object MemoryMB -Sum).Sum, 1)
            $totalCPU = [math]::Round(($chromeData | Measure-Object 'CPU%' -Sum).Sum, 2)
            
            Write-Host ""
            Write-Host "CHROME OVERVIEW:" -ForegroundColor Yellow
            Write-Host "  Total Processes: $totalProcesses | Total CPU: $totalCPU% | Total Memory: $totalMemoryMB MB" -ForegroundColor White
            
            # Show high CPU processes
            $highCpuProcesses = $chromeData | Where-Object { $_.'CPU%' -gt $HighCpuThreshold }
            if ($highCpuProcesses) {
                Write-Host ""
                Write-Host "HIGH CPU PROCESSES (>$HighCpuThreshold% CPU):" -ForegroundColor Red
                $displayCount = if ($ShowAll) { $highCpuProcesses.Count } else { [math]::Min($TopProcessCount, $highCpuProcesses.Count) }
                $highCpuProcesses | Select-Object -First $displayCount | 
                    Format-Table PID, Type, Info, 'CPU%', Memory, Threads, Runtime, 'Start Time' -AutoSize
            }
            
            # Show high memory processes
            $highMemProcesses = $chromeData | Where-Object { $_.MemoryMB -gt $HighMemoryThreshold } | Sort-Object MemoryMB -Descending
            if ($highMemProcesses) {
                Write-Host ""
                Write-Host "HIGH MEMORY PROCESSES (>$HighMemoryThreshold MB):" -ForegroundColor Magenta
                $displayCount = if ($ShowAll) { $highMemProcesses.Count } else { [math]::Min($TopProcessCount, $highMemProcesses.Count) }
                $highMemProcesses | Select-Object -First $displayCount | 
                    Format-Table PID, Type, Info, 'CPU%', Memory, 'Peak Memory', Handles, Runtime -AutoSize
            }
            
            # Group by type summary
            Write-Host ""
            Write-Host "SUMMARY BY PROCESS TYPE:" -ForegroundColor Yellow
            $typeGroups = $chromeData | Group-Object Type | Sort-Object { ($_.Group | Measure-Object 'CPU%' -Sum).Sum } -Descending
            
            foreach ($group in $typeGroups) {
                $groupCPU = [math]::Round(($group.Group | Measure-Object 'CPU%' -Sum).Sum, 2)
                $groupMem = [math]::Round(($group.Group | Measure-Object MemoryMB -Sum).Sum, 1)
                $avgCPU = [math]::Round(($group.Group | Measure-Object 'CPU%' -Average).Average, 2)
                
                $color = if ($groupCPU -gt 10) { "Red" } elseif ($groupCPU -gt 5) { "Yellow" } else { "White" }
                Write-Host "  $($group.Name): " -NoNewline -ForegroundColor $color
                Write-Host "$($group.Count) processes | Total CPU: $groupCPU% | Total Memory: $groupMem MB | Avg CPU: $avgCPU%" -ForegroundColor Gray
            }
            
            # Show Chrome built-in tools reminder
            Write-Host ""
            Write-Host "CHROME BUILT-IN TOOLS:" -ForegroundColor Green
            Write-Host "  Shift+Esc           - Chrome Task Manager (match PIDs with tabs)" -ForegroundColor White
            Write-Host "  chrome://system/    - Detailed system information" -ForegroundColor White
            Write-Host "  chrome://discards/  - Tab resource usage and importance" -ForegroundColor White
            Write-Host "  chrome://process-internals/ - Process breakdown" -ForegroundColor White
            Write-Host "  chrome://memory-internals/  - Memory usage details" -ForegroundColor White
            
            # Show top problematic processes (fixed higher thresholds)
            $problematicProcesses = $chromeData | Where-Object { $_.'CPU%' -gt ([math]::Max($HighCpuThreshold, 5)) -or $_.MemoryMB -gt ([math]::Max($HighMemoryThreshold, 200)) }
            if ($problematicProcesses) {
                Write-Host ""
                Write-Host "ATTENTION: High Resource Usage Detected!" -ForegroundColor Red
                Write-Host "The following Chrome processes may need investigation:" -ForegroundColor Yellow
                foreach ($proc in ($problematicProcesses | Select-Object -First 3)) {
                    Write-Host "  PID $($proc.PID) ($($proc.Type)): $($proc.'CPU%')% CPU, $($proc.Memory) Memory" -ForegroundColor Red
                }
            }

            # Optional export to CSV
            if ($ExportToCsv) {
                try {
                    $exportDir = Split-Path -Parent $ExportPath
                    if ($exportDir -and -not (Test-Path $exportDir)) {
                        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
                    }
                    $chromeData | Select-Object Timestamp, PID, Type, Info, 'CPU%', MemoryMB, Threads, Handles, Runtime, 'Start Time' |
                        Export-Csv -Path $ExportPath -Append -NoTypeInformation
                    Write-Host "Data appended to: $ExportPath" -ForegroundColor Gray
                } catch {
                    Write-Host "Failed to export CSV: $_" -ForegroundColor Yellow
                }
            }
            
        } else {
            Write-Host ""
            Write-Host "No Chrome processes found" -ForegroundColor Gray
            Write-Host "Chrome may not be running or may not be accessible" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host ""
        Write-Host "Error analyzing Chrome processes: $_" -ForegroundColor Red
        Write-Host "Make sure you're running PowerShell as Administrator" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Next refresh in $RefreshInterval seconds... (Press Ctrl+C to exit)" -ForegroundColor Gray
    Write-Host ("=" * 80) -ForegroundColor Green
    
    Start-Sleep -Seconds $RefreshInterval
}