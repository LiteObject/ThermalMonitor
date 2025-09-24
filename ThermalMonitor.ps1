# PowerShell script to monitor CPU/GPU usage, temperatures, and log potential thermal throttling causes
# Requirements: Run as Administrator for full access to system data
# Optional: Install Open Hardware Monitor or HWMonitor for temperature data

# Log file setup
$logFile = "C:\Temp\ThermalMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDir = "C:\Temp"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir
}

# Initialize tracking variables for heat analysis
$script:processHistory = @{}
$script:temperatureHistory = @()
$script:throttleEvents = @()
$script:gpuWarningShown = $false

# Function to write to log file
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
}

# Function to show progress animation
function Show-Progress {
    param($CurrentIteration, $TotalIterations, $Activity)
    $percent = [math]::Round(($CurrentIteration / $TotalIterations) * 100, 1)
    $progressBar = "█" * [math]::Floor($percent / 5) + "░" * (20 - [math]::Floor($percent / 5))
    
    Write-Host "`r[$progressBar] $percent% - $Activity" -NoNewline -ForegroundColor Cyan
}

# Function to show spinning animation
function Show-SpinningCursor {
    param($Index)
    $spinChars = @('|', '/', '-', '\')
    $char = $spinChars[$Index % 4]
    Write-Host "`r$char Collecting data..." -NoNewline -ForegroundColor Yellow
}

# Function to get CPU usage by process with enhanced metrics
function Get-TopCpuProcesses {
    try {
        # Get performance counter data
        $cpuCounters = Get-Counter "\Process(*)\% Processor Time" -ErrorAction Stop
        $cpuCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        
        # Get all running processes for mapping
        $runningProcesses = Get-Process
        $processMap = @{}
        
        # Build process map by name (handle duplicates)
        foreach ($proc in $runningProcesses) {
            $key = $proc.Name
            if (-not $processMap.ContainsKey($key)) {
                $processMap[$key] = @()
            }
            $processMap[$key] += $proc
        }
        
        # Process counter samples and normalize instance names
        $processedData = @{}
        foreach ($sample in $cpuCounters.CounterSamples) {
            if ($sample.InstanceName -eq "_total" -or $sample.InstanceName -eq "idle") {
                continue
            }
            
            # Handle instance names with # (e.g., chrome#1, chrome#2)
            $baseName = $sample.InstanceName -replace '#\d+$', ''
            $normalizedCPU = [math]::Round($sample.CookedValue / $cpuCount, 2)
            
            if ($normalizedCPU -gt 0) {
                if (-not $processedData.ContainsKey($baseName)) {
                    $processedData[$baseName] = @{
                        Name = $baseName
                        CPUPercent = 0
                        WorkingSetMB = 0
                        ThreadCount = 0
                        HandleCount = 0
                        InstanceCount = 0
                    }
                }
                
                # Aggregate CPU usage for multiple instances
                $processedData[$baseName].CPUPercent += $normalizedCPU
                $processedData[$baseName].InstanceCount++
            }
        }
        
        # Add process details from Get-Process
        foreach ($key in $processedData.Keys) {
            if ($processMap.ContainsKey($key)) {
                $procs = $processMap[$key]
                # Sum up metrics for all instances of the same process
                $totalMemory = ($procs | Measure-Object WorkingSet64 -Sum).Sum
                $totalThreads = ($procs | Measure-Object { $_.Threads.Count } -Sum).Sum
                $totalHandles = ($procs | Measure-Object HandleCount -Sum).Sum
                
                $processedData[$key].WorkingSetMB = [math]::Round($totalMemory / 1MB, 2)
                $processedData[$key].ThreadCount = $totalThreads
                $processedData[$key].HandleCount = $totalHandles
            }
        }
        
        # Convert to array and sort by CPU usage
        $processes = $processedData.Values | 
            Sort-Object CPUPercent -Descending |
            Select-Object -First 10
            
        return $processes
        
    } catch {
        Write-Log "Error getting CPU performance counters: $_"
        # Fallback method
        $processes = Get-Process | Where-Object { $_.CPU -gt 0 } | 
            Sort-Object CPU -Descending | 
            Select-Object -First 10 |
            Select-Object Name, ID, 
                @{Name="CPUTime";Expression={[math]::Round($_.CPU,2)}}, 
                @{Name="WorkingSetMB";Expression={[math]::Round($_.WorkingSet64/1MB,2)}},
                @{Name="ThreadCount";Expression={$_.Threads.Count}}
        return $processes
    }
}

# Function to get GPU usage with process mapping
function Get-GpuUsage {
    try {
        # Check Windows version and GPU driver support
        $osVersion = [System.Environment]::OSVersion.Version
        if ($osVersion.Major -lt 10 -or ($osVersion.Major -eq 10 -and $osVersion.Build -lt 17763)) {
            if (-not $script:gpuWarningShown) {
                Write-Log "GPU monitoring requires Windows 10 build 17763 or higher"
                $script:gpuWarningShown = $true
            }
            return $null
        }
        
        # Try to get GPU usage per process
        $gpuCounters = Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction Stop
        
        $gpuData = $gpuCounters.CounterSamples | 
            Where-Object { $_.CookedValue -gt 0 } |
            ForEach-Object {
                # Parse the instance name to extract process name
                $instanceName = $_.InstanceName
                $processName = if ($instanceName -match '^([^_]+)_') {
                    $matches[1]
                } else {
                    $instanceName
                }
                
                [PSCustomObject]@{
                    Name = $processName
                    GPUPercent = [math]::Round($_.CookedValue, 2)
                    EngineType = if ($instanceName -match 'engtype_(\w+)') { $matches[1] } else { "Unknown" }
                }
            } |
            Group-Object Name |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    GPUPercent = [math]::Round(($_.Group | Measure-Object GPUPercent -Sum).Sum, 2)
                }
            } |
            Sort-Object GPUPercent -Descending |
            Select-Object -First 10
        
        return $gpuData
        
    } catch {
        if (-not $script:gpuWarningShown) {
            Write-Log "GPU counters unavailable: $_"
            $script:gpuWarningShown = $true
        }
        return $null
    }
}

# Helper function to convert Celsius to Fahrenheit
function ConvertTo-Fahrenheit {
    param($Celsius)
    return [math]::Round(($Celsius * 9/5) + 32, 1)
}

# Enhanced temperature function with averaging
function Get-CpuTemperature {
    $temperature = $null
    
    # Try Open Hardware Monitor first
    try {
        $wmi = Get-WmiObject -Namespace "root\OpenHardwareMonitor" -Class Sensor -ErrorAction Stop
        $cpuTemps = $wmi | Where-Object { $_.SensorType -eq "Temperature" -and $_.Name -like "*CPU*" }
        
        if ($cpuTemps) {
            $avgTemp = ($cpuTemps | Measure-Object -Property Value -Average).Average
            $maxTemp = ($cpuTemps | Measure-Object -Property Value -Maximum).Maximum
            $temperature = @{
                Average = [math]::Round($avgTemp, 1)
                AverageF = ConvertTo-Fahrenheit $avgTemp
                Max = [math]::Round($maxTemp, 1)
                MaxF = ConvertTo-Fahrenheit $maxTemp
                Source = "OpenHardwareMonitor"
                Details = $cpuTemps | Select-Object Name, Value, @{Name="ValueF";Expression={ConvertTo-Fahrenheit $_.Value}}
            }
        }
    } catch [System.Management.ManagementException] {
        if ($_.Exception.Message -like "*Invalid namespace*") {
            # Silently fall back to ACPI sensors
        } else {
            Write-Log "Error accessing Open Hardware Monitor: $_"
        }
    } catch {
        Write-Log "Unexpected error with Open Hardware Monitor: $_"
    }
    
    # Fall back to Windows built-in thermal zones if no temperature data yet
    if (-not $temperature) {
        try {
            $thermalZones = Get-WmiObject -Namespace "root\wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
            if ($thermalZones) {
                $temps = $thermalZones | ForEach-Object {
                    ($_.CurrentTemperature / 10) - 273.15
                } | Where-Object { $_ -gt 0 -and $_ -lt 150 } # Filter out invalid readings
                
                if ($temps) {
                    $avgTemp = ($temps | Measure-Object -Average).Average
                    $maxTemp = ($temps | Measure-Object -Maximum).Maximum
                    $temperature = @{
                        Average = [math]::Round($avgTemp, 1)
                        AverageF = ConvertTo-Fahrenheit $avgTemp
                        Max = [math]::Round($maxTemp, 1)
                        MaxF = ConvertTo-Fahrenheit $maxTemp
                        Source = "Windows Thermal Zones"
                        Details = "ACPI thermal zone data"
                    }
                }
            }
        } catch {
            # No temperature sensors accessible
        }
    }
    
    return $temperature
}

# Enhanced throttling detection
function Test-ThermalThrottling {
    $cpu = Get-CimInstance Win32_Processor
    $currentClock = $cpu.CurrentClockSpeed
    $maxClock = $cpu.MaxClockSpeed
    $throttlePercent = [math]::Round(($currentClock / $maxClock) * 100, 2)
    
    return @{
        IsThrottling = ($throttlePercent -lt 85)
        CurrentClock = $currentClock
        MaxClock = $maxClock
        Percentage = $throttlePercent
    }
}

# Function to analyze and rank heat-causing processes
function Get-HeatCulprits {
    param(
        $ProcessHistory,
        $TemperatureHistory,
        $ThrottleEvents,
        $TotalIterations
    )
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "           HEAT ANALYSIS REPORT                " -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    
    Write-Log ""
    Write-Log "===== HEAT ANALYSIS REPORT ====="
    
    # Calculate average CPU usage per process
    $processAverages = @{}
    foreach ($process in $ProcessHistory.Keys) {
        $avgCPU = if ($ProcessHistory[$process].CPU.Count -gt 0) {
            ($ProcessHistory[$process].CPU | Measure-Object -Average).Average
        } else { 0 }
        
        $maxCPU = if ($ProcessHistory[$process].CPU.Count -gt 0) {
            ($ProcessHistory[$process].CPU | Measure-Object -Maximum).Maximum
        } else { 0 }
        
        $avgMem = if ($ProcessHistory[$process].Memory.Count -gt 0) {
            ($ProcessHistory[$process].Memory | Measure-Object -Average).Average
        } else { 0 }
        
        $frequency = $ProcessHistory[$process].CPU.Count
        $frequencyPercent = ($frequency / $TotalIterations) * 100
        
        # Improved heat score calculation:
        # - Average CPU * duration factor (sustained load)
        # - Peak CPU impact
        # - Memory pressure consideration
        $sustainedLoad = $avgCPU * ($frequencyPercent / 100)  # CPU% × time presence
        $peakLoad = $maxCPU * 0.3  # Peak spikes matter less
        $memoryPressure = [math]::Min($avgMem / 1000, 10)  # Cap memory contribution at 10 points
        
        $processAverages[$process] = @{
            AvgCPU = [math]::Round($avgCPU, 2)
            MaxCPU = [math]::Round($maxCPU, 2)
            AvgMemoryMB = [math]::Round($avgMem, 2)
            Frequency = $frequency
            FrequencyPercent = [math]::Round($frequencyPercent, 1)
            HeatScore = [math]::Round($sustainedLoad + $peakLoad + $memoryPressure, 2)
        }
    }
    
    # Sort by heat score
    $topCulprits = $processAverages.GetEnumerator() | 
        Where-Object { $_.Value.HeatScore -gt 0 } |
        Sort-Object { $_.Value.HeatScore } -Descending | 
        Select-Object -First 5
    
    Write-Host "🔥 TOP HEAT-CAUSING PROCESSES:" -ForegroundColor Yellow
    Write-Log "Top Heat-Causing Processes (ranked by heat score):"
    
    $rank = 1
    foreach ($culprit in $topCulprits) {
        $color = if ($culprit.Value.HeatScore -gt 50) { "Red" } 
                 elseif ($culprit.Value.HeatScore -gt 25) { "Yellow" } 
                 else { "White" }
                 
        Write-Host "  $rank. $($culprit.Key)" -ForegroundColor $color
        $heatScoreText = "     Heat Score: $($culprit.Value.HeatScore) | Avg CPU: $($culprit.Value.AvgCPU)% | Max CPU: $($culprit.Value.MaxCPU)%"
        Write-Host $heatScoreText -ForegroundColor $color
        $memoryText = "     Memory: $($culprit.Value.AvgMemoryMB) MB | Present: $($culprit.Value.FrequencyPercent)% of time"
        Write-Host $memoryText -ForegroundColor Gray
        
        Write-Log "  $rank. $($culprit.Key) - Heat Score: $($culprit.Value.HeatScore)"
        $avgCpuLogText = "     Average CPU: $($culprit.Value.AvgCPU)%, Max CPU: $($culprit.Value.MaxCPU)%"
        Write-Log $avgCpuLogText
        Write-Log "     Average Memory: $($culprit.Value.AvgMemoryMB) MB"
        $presenceLogText = "     Presence: $($culprit.Value.Frequency)/$TotalIterations cycles ($($culprit.Value.FrequencyPercent)%)"
        Write-Log $presenceLogText
        $rank++
    }
    
    # Temperature analysis
    if ($TemperatureHistory.Count -gt 0) {
        $avgSystemTemp = ($TemperatureHistory | Measure-Object -Average).Average
        $maxSystemTemp = ($TemperatureHistory | Measure-Object -Maximum).Maximum
        
        Write-Host ""
        Write-Host "TEMPERATURE SUMMARY:" -ForegroundColor Cyan
        $avgTempC = [math]::Round($avgSystemTemp, 1)
        $avgTempF = ConvertTo-Fahrenheit $avgTempC
        $avgTempText = "   Average: $avgTempC°C ($avgTempF°F)"
        Write-Host $avgTempText -ForegroundColor White
        $maxTempC = [math]::Round($maxSystemTemp, 1)
        $maxTempF = ConvertTo-Fahrenheit $maxTempC
        $maxTempText = "   Maximum: $maxTempC°C ($maxTempF°F)"
        Write-Host $maxTempText -ForegroundColor $(if ($maxSystemTemp -gt 85) { "Red" } else { "White" })
        
        Write-Log ""
        Write-Log "Temperature Summary:"
        $avgTempLog = "  Average Temperature: $avgTempC°C ($avgTempF°F)"
        Write-Log $avgTempLog
        $maxTempLog = "  Maximum Temperature: $maxTempC°C ($maxTempF°F)"
        Write-Log $maxTempLog
        
        if ($maxSystemTemp -gt 85) {
            Write-Host "   ⚠️ HIGH TEMPERATURE DETECTED!" -ForegroundColor Red
            Write-Log "  WARNING: High temperature detected (greater than 85°C / 185°F)"
        }
    } else {
        Write-Host ""
        Write-Host "🌡️ No temperature data available" -ForegroundColor Gray
        Write-Log "No temperature sensors accessible during monitoring"
    }
    
    # Throttling analysis
    if ($ThrottleEvents.Count -gt 0) {
        $throttleRate = [math]::Round(($ThrottleEvents.Count / $TotalIterations) * 100, 1)
        Write-Host ""
        $throttleMessage = "⚡ THROTTLING EVENTS: $($ThrottleEvents.Count)/$TotalIterations cycles ($throttleRate%)"
        Write-Host $throttleMessage -ForegroundColor $(if ($throttleRate -gt 50) { "Red" } else { "Yellow" })
        Write-Log ""
        $throttleLogMessage = "Throttling Events: $($ThrottleEvents.Count)/$TotalIterations cycles ($throttleRate%)"
        Write-Log $throttleLogMessage
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Red
    Write-Log "===== END OF HEAT ANALYSIS ====="
}

# Main monitoring loop
Write-Host "===============================================" -ForegroundColor Green
Write-Host "           THERMAL MONITOR STARTED            " -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Monitoring System Performance..." -ForegroundColor Yellow
Write-Host "📁 Log file location: $logFile" -ForegroundColor Cyan
Write-Host "⏱️ Duration: 5 minutes (30 cycles, 10s intervals)" -ForegroundColor Cyan
Write-Host "💡 Check the log file for detailed results!" -ForegroundColor White
Write-Host ""

Write-Log "Starting thermal monitoring..."

$script:monitorDuration = 300 # Monitor for 5 minutes (300 seconds)
$script:interval = 10 # Check every 10 seconds
$script:iterations = [math]::Ceiling($monitorDuration / $interval)

for ($i = 1; $i -le $iterations; $i++) {
    # Show progress
    Show-Progress -CurrentIteration $i -TotalIterations $iterations -Activity "Cycle $i of $iterations"
    Write-Host ""
    
    Write-Log "----- Monitoring Cycle $i -----"

    # Show spinning animation while collecting data
    Show-SpinningCursor -Index $i
    Start-Sleep -Milliseconds 500
    
    # Get CPU usage
    $cpuProcesses = Get-TopCpuProcesses
    Write-Log "Top CPU-consuming processes:"
    if ($cpuProcesses) {
        $cpuProcesses | Select-Object -First 5 | ForEach-Object {
            # Track process history for heat analysis
            if (-not $script:processHistory.ContainsKey($_.Name)) {
                $script:processHistory[$_.Name] = @{ CPU = @(); Memory = @(); GPU = @() }
            }
            
            if ($_.CPUPercent) {
                $script:processHistory[$_.Name].CPU += $_.CPUPercent
                $script:processHistory[$_.Name].Memory += $_.WorkingSetMB
                $processLogText = "  Process: $($_.Name), CPU: $($_.CPUPercent)%, Memory: $($_.WorkingSetMB)MB, Threads: $($_.ThreadCount)"
                Write-Log $processLogText
            } else {
                Write-Log "  Process: $($_.Name), PID: $($_.ID), CPU Time: $($_.CPUTime)s, Memory: $($_.WorkingSetMB)MB"
            }
        }
    }

    # Get GPU usage
    $gpuUsage = Get-GpuUsage
    if ($gpuUsage) {
        Write-Log "GPU usage information:"
        $gpuUsage | Select-Object -First 5 | ForEach-Object {
            $gpuProcessLogText = "  Process: $($_.Name), GPU Usage: $($_.GPUPercent)%"
            Write-Log $gpuProcessLogText
            
            # Track GPU usage in process history
            if ($script:processHistory.ContainsKey($_.Name)) {
                $script:processHistory[$_.Name].GPU += $_.GPUPercent
            }
        }
    }

    # Get CPU temperature
    $cpuTemp = Get-CpuTemperature
    if ($cpuTemp) {
        Write-Log "CPU Temperature ($($cpuTemp.Source)):"
        $script:temperatureHistory += $cpuTemp.Average
        $tempLogText = "  Average: $($cpuTemp.Average)°C ($($cpuTemp.AverageF)°F), Max: $($cpuTemp.Max)°C ($($cpuTemp.MaxF)°F)"
        Write-Log $tempLogText
        
        # Show temperature warning in console
        if ($cpuTemp.Average -gt 85) {
            $highTempText = "`rWARNING: HIGH TEMP: $($cpuTemp.Average)°C ($($cpuTemp.AverageF)°F)"
            Write-Host $highTempText -ForegroundColor Red
        }
        
        if ($cpuTemp.Details -and $cpuTemp.Details -isnot [string]) {
            $cpuTemp.Details | ForEach-Object {
                $detailTempLogText = "  $($_.Name): $($_.Value)°C ($($_.ValueF)°F)"
                Write-Log $detailTempLogText
            }
        }
    } else {
        Write-Log "No temperature sensors accessible"
    }

    # Check for throttling
    $throttleStatus = Test-ThermalThrottling
    if ($throttleStatus.IsThrottling) {
        $script:throttleEvents += $i
        $throttleLogText = "THROTTLING DETECTED: Current clock: $($throttleStatus.CurrentClock) MHz, Max: $($throttleStatus.MaxClock) MHz ($($throttleStatus.Percentage)%)"
        Write-Log $throttleLogText
        $throttleConsoleText = "`r⚡ Throttling detected at $($throttleStatus.Percentage)%"
        Write-Host $throttleConsoleText -ForegroundColor Yellow
    } else {
        $noThrottleLogText = "No throttling: Current clock: $($throttleStatus.CurrentClock) MHz ($($throttleStatus.Percentage)% of max)"
        Write-Log $noThrottleLogText
    }

    # Clear the spinning cursor and show completion
    Write-Host "`rCycle $i/$iterations completed ✓" -ForegroundColor Green
    
    # Wait for the next interval
    if ($i -lt $iterations) {
        Start-Sleep -Seconds ($interval - 1)
    }
}

# Analyze and report heat culprits
Get-HeatCulprits -ProcessHistory $script:processHistory -TemperatureHistory $script:temperatureHistory -ThrottleEvents $script:throttleEvents -TotalIterations $script:iterations

Write-Log ""
Write-Log "Monitoring complete. Log saved to $logFile"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "         MONITORING COMPLETED! ✓              " -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Full log saved to: $logFile" -ForegroundColor Cyan
Write-Host "🔍 Open the log file to review detailed results" -ForegroundColor White
Write-Host ""