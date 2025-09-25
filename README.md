# Thermal Monitor

A comprehensive PowerShell toolkit for monitoring and diagnosing system thermal issues on Windows. Includes two specialized scripts:

- **ThermalMonitor.ps1**: Main system thermal monitoring with CPU/GPU usage, temperatures, and thermal throttling detection
- **ChromeTabMonitor.ps1**: Real-time Chrome process analysis to identify resource-heavy tabs and extensions

Helps identify resource-heavy processes contributing to overheating. Optional integration with Open Hardware Monitor for enhanced temperature data. Ideal for diagnosing performance issues and Chrome-specific resource consumption.

---

## How the Script Works

- **Logs Data:** Saves output to a log file in `C:\Temp` with a timestamped filename (e.g., `ThermalMonitor_20250722_083512.log`).
- **CPU Usage:** Uses performance counters to get real-time CPU usage percentage for the top 10 processes, with intelligent aggregation of multiple process instances and fallback to CPU time if counters aren't available.
- **GPU Usage:** Attempts to retrieve GPU engine utilization using Windows performance counters with proper process name parsing and aggregation (availability varies by system and GPU).
- **CPU Temperature:** Tries Open Hardware Monitor first with silent fallback to Windows built-in thermal zones. Includes temperature averaging and validation. Displays temperatures in both Celsius and Fahrenheit for convenience.
- **Process Tracking:** Maintains historical data for each process across all monitoring cycles to identify sustained heat sources.
- **Heat Analysis:** Calculates a "heat score" for each process based on average CPU usage, peak usage, memory consumption, and time presence to identify the most likely culprits.
- **Thermal Throttling Detection:** Compares current CPU clock speed to max clock speed and tracks throttling events throughout monitoring.
- **Monitoring Loop:** Runs for 5 minutes, checking every 10 seconds, and logs all data with real-time warnings for high temperatures and throttling.
- **Visual Feedback:** Displays progress bars, spinning animations, colored status messages, and a comprehensive heat analysis report at the end.

## Prerequisites

- **Run as Administrator:** Performance counters and some WMI queries require elevated privileges. Right-click PowerShell and select "Run as Administrator."
- **Open Hardware Monitor (Optional):** For enhanced temperature data, download and run Open Hardware Monitor before executing the script. The script will attempt to use Windows built-in thermal sensors as fallback.
- **Windows 10/11:** GPU performance counters work best on modern Windows versions with supported GPUs and drivers.

## How to Use

### ThermalMonitor.ps1 (Main System Monitor)
1. Download and save the script as `ThermalMonitor.ps1` to any directory of your choice.
2. Open PowerShell as Administrator.
3. Navigate to the directory where you saved the script (e.g., `cd C:\Downloads` or `cd "C:\Your\Preferred\Path"`).
4. Run the script: `.\ThermalMonitor.ps1`.
5. Watch the progress indicators in the console.
6. Check the log file in `C:\Temp` for detailed results.

### ChromeTabMonitor.ps1 (Chrome-Specific Analysis)
1. Save `ChromeTabMonitor.ps1` to your preferred directory.
2. Open PowerShell (Administrator recommended for full access).
3. Navigate to the script directory.
4. Run with default settings: `.\ChromeTabMonitor.ps1`
5. Or customize parameters:
   ```powershell
   .\ChromeTabMonitor.ps1 -RefreshInterval 3 -HighCpuThreshold 2 -ExportToCsv
   ```

#### ChromeTabMonitor Parameters:
- **RefreshInterval**: Update frequency in seconds (1-300, default: 5)
- **TopProcessCount**: Number of top processes to display (default: 10)
- **ShowAll**: Show all Chrome processes instead of just top ones
- **HighCpuThreshold**: CPU percentage threshold for highlighting (default: 1%)
- **HighMemoryThreshold**: Memory threshold in MB for highlighting (default: 100MB)
- **ExportToCsv**: Enable CSV export of process data
- **ExportPath**: Custom path for CSV export (auto-generated if not specified)


## Interpreting the Results

### ThermalMonitor.ps1 Results

#### Heat Analysis Report
The script automatically generates a comprehensive heat analysis report at the end, ranking processes by their "heat score":

- **Heat Score Calculation:** Combines sustained CPU load (average CPU × time present), peak CPU impact, and memory pressure
- **Top Heat Culprits:** Shows the top 5 processes most likely responsible for system heating
- **Process Metrics:** Displays average CPU usage, maximum CPU usage, memory consumption, and percentage of time the process was active
- **Color Coding:** Red indicates high heat scores (>50), yellow indicates moderate scores (>25)

### Temperature Analysis
- **Temperature Averaging:** Shows average and maximum temperatures throughout the monitoring period in both Celsius and Fahrenheit
- **High Temperature Warnings:** Alerts when temperatures exceed 85°C (185°F)
- **Multiple Sources:** Uses Open Hardware Monitor data when available, falls back to Windows thermal zones
- **Dual Scale Display:** All temperature readings are shown in both °C and °F for user convenience

### Throttling Detection
- **Real-time Monitoring:** Tracks CPU clock speed changes throughout monitoring
- **Throttling Events:** Reports frequency and percentage of time throttling occurred
- **Performance Impact:** Shows current vs maximum clock speeds to assess throttling severity

### ChromeTabMonitor.ps1 Results

#### Real-Time Chrome Analysis
- **Process Overview:** Shows total Chrome processes, aggregate CPU usage, and total memory consumption
- **High Resource Processes:** Automatically highlights processes exceeding your configured CPU and memory thresholds
- **Process Classification:** Identifies process types (Main, Tab, Extension, GPU, Audio Service, etc.) with additional context
- **Resource Metrics:** Displays CPU percentage, memory usage, thread count, handles, and runtime for each process
- **Problematic Process Alerts:** Special highlighting for processes with very high resource usage that may need investigation

#### Chrome Process Types Explained
- **Main/Browser Main:** The primary Chrome browser process
- **Tab:** Individual website tabs (site-isolated for security)
- **Extension:** Browser extensions with extension ID hints when available
- **GPU:** Graphics processing for hardware acceleration
- **Audio/Network/Storage Service:** Specialized utility processes
- **App:** Chrome web applications

#### CSV Export (Optional)
When enabled, exports timestamped data including all process metrics for historical analysis and trend identification.

## Advanced Features

### ThermalMonitor.ps1 Features
- **Process Instance Aggregation:** Handles multiple instances of the same process (e.g., chrome#1, chrome#2) by combining their resource usage
- **Smart GPU Detection:** Automatically detects Windows version compatibility for GPU monitoring (requires Windows 10 build 17763+)
- **Enhanced Error Handling:** Graceful fallbacks when performance counters or temperature sensors are unavailable
- **Sustained Load Analysis:** Focuses on processes that consistently consume resources over time rather than brief spikes
- **Memory Pressure Consideration:** Includes memory usage in heat calculations as high memory usage can contribute to thermal load

### ChromeTabMonitor.ps1 Features
- **Performance Counter Integration:** Uses Windows performance counters for accurate real-time CPU measurements with fallback to time-based estimates
- **Batch WMI Queries:** Optimized process information retrieval for better performance with many Chrome processes
- **Configurable Thresholds:** Customizable CPU and memory thresholds for highlighting problematic processes
- **Process Type Intelligence:** Advanced Chrome process classification with context clues (extension IDs, app URLs, etc.)
- **Memory Management:** Periodic garbage collection for long-running monitoring sessions
- **CSV Data Export:** Optional timestamped data export for trend analysis and historical review
- **Error Resilience:** Handles access-denied scenarios gracefully while preserving visible metrics

## Customization

### ThermalMonitor.ps1 Customization
- **Duration:** Modify `$monitorDuration` (default: 300 seconds) to change monitoring time
- **Interval:** Adjust `$interval` (default: 10 seconds) to change sampling frequency
- **Process Count:** The script tracks top 10 processes internally but displays top 5 in logs for clarity
- **Heat Score Tuning:** Advanced users can modify the heat score calculation weights in the `Get-HeatCulprits` function

### ChromeTabMonitor.ps1 Customization
- **Refresh Rate:** Use `-RefreshInterval` parameter (1-300 seconds, default: 5)
- **Display Count:** Adjust `-TopProcessCount` to show more/fewer processes (default: 10)
- **Threshold Tuning:** Modify `-HighCpuThreshold` and `-HighMemoryThreshold` to match your system's baseline
- **Export Configuration:** Customize CSV export path and enable/disable with `-ExportToCsv` and `-ExportPath`
- **Display Mode:** Use `-ShowAll` to see all Chrome processes regardless of resource usage

## Troubleshooting

### General Issues
- **Permission Errors:** Always run PowerShell as Administrator for full functionality
- **Performance Counter Issues:** Both scripts include fallbacks if performance counters are unavailable

### ThermalMonitor.ps1 Issues
- **No Temperature Data:** Install Open Hardware Monitor or check if your system exposes ACPI thermal zones
- **No GPU Data:** Ensure you have Windows 10 build 17763+ with WDDM 2.0+ drivers

### ChromeTabMonitor.ps1 Issues
- **No Chrome Processes Found:** Ensure Chrome is running before starting the monitor
- **Access Denied Errors:** Some Chrome processes may be protected; run as Administrator for complete access
- **High CPU Usage from Monitor:** Reduce refresh frequency with `-RefreshInterval 10` or higher
- **CSV Export Fails:** Check that the export directory exists and is writable
- **Inaccurate CPU Readings:** Performance counter availability varies by system; the script falls back to time-based estimates

## Use Cases

### Identifying System Overheating
1. Run `ThermalMonitor.ps1` during normal usage
2. Check heat analysis report for top resource consumers
3. If Chrome appears as a major heat source, run `ChromeTabMonitor.ps1` for detailed tab analysis
4. Use CSV export from ChromeTabMonitor for pattern analysis over time

### Chrome Performance Optimization
1. Run `ChromeTabMonitor.ps1` with low thresholds to catch all resource usage
2. Enable CSV export for trend analysis
3. Identify problematic extensions, tabs, or background processes
4. Cross-reference with Chrome's built-in Task Manager (Shift+Esc) for additional context
