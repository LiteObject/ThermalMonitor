# Thermal Monitor

A PowerShell script to monitor and log CPU/GPU usage, system temperatures, and potential thermal throttling causes on Windows laptops. Helps identify resource-heavy processes contributing to overheating. Optional integration with Open Hardware Monitor for temperature data. Ideal for diagnosing performance issues.

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
1. Download and save the script as `ThermalMonitor.ps1` to any directory of your choice.
2. Open PowerShell as Administrator.
3. Navigate to the directory where you saved the script (e.g., `cd C:\Downloads` or `cd "C:\Your\Preferred\Path"`).
4. Run the script: `.\ThermalMonitor.ps1`.
5. Watch the progress indicators in the console.
6. Check the log file in `C:\Temp` for detailed results.


## Interpreting the Results

### Heat Analysis Report
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

## Advanced Features

- **Process Instance Aggregation:** Handles multiple instances of the same process (e.g., chrome#1, chrome#2) by combining their resource usage
- **Smart GPU Detection:** Automatically detects Windows version compatibility for GPU monitoring (requires Windows 10 build 17763+)
- **Enhanced Error Handling:** Graceful fallbacks when performance counters or temperature sensors are unavailable
- **Sustained Load Analysis:** Focuses on processes that consistently consume resources over time rather than brief spikes
- **Memory Pressure Consideration:** Includes memory usage in heat calculations as high memory usage can contribute to thermal load

## Customization

- **Duration:** Modify `$monitorDuration` (default: 300 seconds) to change monitoring time
- **Interval:** Adjust `$interval` (default: 10 seconds) to change sampling frequency
- **Process Count:** The script tracks top 10 processes internally but displays top 5 in logs for clarity
- **Heat Score Tuning:** Advanced users can modify the heat score calculation weights in the `Get-HeatCulprits` function

## Troubleshooting

- **No Temperature Data:** Install Open Hardware Monitor or check if your system exposes ACPI thermal zones
- **No GPU Data:** Ensure you have Windows 10 build 17763+ with WDDM 2.0+ drivers
- **Permission Errors:** Always run PowerShell as Administrator for full functionality
- **Performance Counter Issues:** The script includes fallbacks if performance counters are unavailable
