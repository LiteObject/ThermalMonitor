# PowerShell script to monitor CPU/GPU usage, temperatures, and log potential thermal throttling causes
# Requirements: Run as Administrator for full access to system data
# Optional: Install Open Hardware Monitor or HWMonitor for temperature data

# Log file setup
$logFile = "C:\Temp\ThermalMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDir = "C:\Temp"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir
}

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

# Function to get CPU usage by process
function Get-TopCpuProcesses {
    try {
        $cpuCounters = Get-Counter "\Process(*)\% Processor Time" -ErrorAction Stop
        $processes = $cpuCounters.CounterSamples | 
            Where-Object { $_.InstanceName -ne "_total" -and $_.InstanceName -ne "idle" -and $_.CookedValue -gt 0 } |
            Sort-Object CookedValue -Descending |
            Select-Object -First 5 |
            Select-Object @{Name="Name";Expression={$_.InstanceName}}, @{Name="CPUPercent";Expression={[math]::Round($_.CookedValue,2)}}
        return $processes
    } catch {
        # Fallback to process CPU time if performance counters fail
        $processes = Get-Process | Where-Object { $_.CPU -gt 0 } | Sort-Object CPU -Descending | Select-Object -First 5 |
            Select-Object Name, ID, @{Name="CPUTime";Expression={[math]::Round($_.CPU,2)}}
        return $processes
    }
}

# Function to get GPU usage (requires Windows 10/11)
function Get-GpuUsage {
    try {
        # Try modern GPU performance counters first
        $gpuCounters = Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction Stop
        $gpuData = $gpuCounters.CounterSamples | 
            Where-Object { $_.CookedValue -gt 0 } |
            Sort-Object CookedValue -Descending |
            Select-Object -First 5 |
            Select-Object @{Name="Name";Expression={$_.InstanceName}}, @{Name="GPUPercent";Expression={[math]::Round($_.CookedValue,2)}}
        return $gpuData
    } catch {
        try {
            # Fallback to GPU process memory counters
            $gpuData = Get-CimInstance -Namespace "root\cimv2" -ClassName Win32_PerfRawData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop |
                Where-Object { $_.Name -like "*engtype_3D*" } |
                Select-Object -First 5 |
                Select-Object Name, @{Name="GPUPercent";Expression={"Data not available"}}
            return $gpuData
        } catch {
            return $null
        }
    }
}

# Function to get CPU temperature (requires Open Hardware Monitor running)
function Get-CpuTemperature {
    try {
        # Try Open Hardware Monitor first
        $wmi = Get-WmiObject -Namespace "root\OpenHardwareMonitor" -Class Sensor -ErrorAction Stop
        $cpuTemp = $wmi | Where-Object { $_.SensorType -eq "Temperature" -and $_.Name -like "*CPU*" } |
            Select-Object Name, Value
        if ($cpuTemp) {
            return $cpuTemp
        }
    } catch {
        # Try Windows built-in thermal zones as fallback
        try {
            $thermalZones = Get-WmiObject -Namespace "root\wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
            if ($thermalZones) {
                $tempData = $thermalZones | ForEach-Object {
                    $tempC = [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
                    [PSCustomObject]@{
                        Name = "Thermal Zone"
                        Value = $tempC
                    }
                }
                return $tempData
            }
        } catch {
            return "No temperature sensors accessible. Try running Open Hardware Monitor or check if thermal sensors are available."
        }
    }
    return "Open Hardware Monitor not running and no accessible thermal sensors found"
}

# Function to check for thermal throttling (basic check via CPU clock speed)
function Check-ThermalThrottling {
    $cpu = Get-CimInstance Win32_Processor
    $currentClock = $cpu.CurrentClockSpeed
    $maxClock = $cpu.MaxClockSpeed
    $throttlePercent = [math]::Round(($currentClock / $maxClock) * 100, 2)
    if ($throttlePercent -lt 80) {
        return "Possible thermal throttling detected. Current clock: $currentClock MHz, Max clock: $maxClock MHz ($throttlePercent%)"
    } else {
        return "No significant throttling detected. Current clock: $currentClock MHz, Max clock: $maxClock MHz ($throttlePercent%)"
    }
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

$monitorDuration = 300 # Monitor for 5 minutes (300 seconds)
$interval = 10 # Check every 10 seconds
$iterations = [math]::Ceiling($monitorDuration / $interval)

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
    Write-Log "Top 5 CPU-consuming processes:"
    if ($cpuProcesses) {
        $cpuProcesses | ForEach-Object {
            if ($_.CPUPercent) {
                Write-Log "Process: $($_.Name), CPU Usage: $($_.CPUPercent)%"
            } else {
                Write-Log "Process: $($_.Name), PID: $($_.ID), CPU Time: $($_.CPUTime)s"
            }
        }
    } else {
        Write-Log "No CPU process data available"
    }

    # Get GPU usage
    $gpuUsage = Get-GpuUsage
    Write-Log "GPU usage information:"
    if ($gpuUsage) {
        $gpuUsage | ForEach-Object {
            if ($_.GPUPercent -is [string]) {
                Write-Log "GPU Engine: $($_.Name), Status: $($_.GPUPercent)"
            } else {
                Write-Log "GPU Engine: $($_.Name), Usage: $($_.GPUPercent)%"
            }
        }
    } else {
        Write-Log "No GPU usage data available (GPU performance counters not supported on this system)"
    }

    # Get CPU temperature
    $cpuTemp = Get-CpuTemperature
    Write-Log "CPU Temperature:"
    if ($cpuTemp -is [string]) {
        Write-Log $cpuTemp
    } else {
        $cpuTemp | ForEach-Object {
            Write-Log "$($_.Name): $($_.Value)°C"
        }
    }

    # Check for throttling
    $throttleStatus = Check-ThermalThrottling
    Write-Log $throttleStatus

    # Clear the spinning cursor and show completion
    Write-Host "`rCycle $i/$iterations completed ✓" -ForegroundColor Green
    
    # Wait for the next interval (minus the time already spent)
    if ($i -lt $iterations) {
        Start-Sleep -Seconds ($interval - 1)  # -1 because we already slept for 0.5 seconds
    }
}

Write-Log "Monitoring complete. Log saved to $logFile"
Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "         MONITORING COMPLETED! ✓              " -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Full log saved to: $logFile" -ForegroundColor Cyan
Write-Host "🔍 Open the log file to review detailed results" -ForegroundColor White
Write-Host ""