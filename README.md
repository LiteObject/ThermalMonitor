# ThermalMonitor

A PowerShell script to monitor and log CPU/GPU usage, system temperatures, and potential thermal throttling causes on Windows laptops. Helps identify resource-heavy processes contributing to overheating. Optional integration with Open Hardware Monitor for temperature data. Ideal for diagnosing performance issues.

---

## How the Script Works

- **Logs Data:** Saves output to a log file in `C:\Temp` with a timestamped filename (e.g., `ThermalMonitor_20250722_083512.log`).
- **CPU Usage:** Uses performance counters to get real-time CPU usage percentage for the top 5 processes, with fallback to CPU time if counters aren't available.
- **GPU Usage:** Attempts to retrieve GPU engine utilization using Windows performance counters (availability varies by system and GPU).
- **CPU Temperature:** Tries Open Hardware Monitor first, then falls back to Windows built-in thermal zones if available.
- **Thermal Throttling Check:** Compares current CPU clock speed to max clock speed to detect potential throttling.
- **Monitoring Loop:** Runs for 5 minutes, checking every 10 seconds, and logs all data.
- **Visual Feedback:** Displays progress bars, spinning animations, and colored status messages during monitoring.

## Prerequisites

- **Run as Administrator:** Performance counters and some WMI queries require elevated privileges. Right-click PowerShell and select "Run as Administrator."
- **Open Hardware Monitor (Optional):** For enhanced temperature data, download and run Open Hardware Monitor before executing the script. The script will attempt to use Windows built-in thermal sensors as fallback.
- **Windows 10/11:** GPU performance counters work best on modern Windows versions with supported GPUs and drivers.

## How to Use

1. Save the script as `ThermalMonitor.ps1`.
2. Open PowerShell as Administrator.
3. Navigate to the script's directory (e.g., `cd C:\Scripts`).
4. Run the script: `.\ThermalMonitor.ps1`.
5. Watch the progress indicators in the console.
6. Check the log file in `C:\Temp` for detailed results.

## Interpreting the Log

- **High CPU/GPU Usage:** Processes consistently appearing in the top 5 with high CPU or GPU usage (e.g., >50%) are likely causing heat.
- **Temperature Spikes:** If using Open Hardware Monitor, look for temperatures above 85°C correlating with specific processes.
- **Throttling Indicators:** If the CPU clock speed is significantly below the max (e.g., <80%), throttling is likely occurring, and the listed processes are suspects.

## Notes

- **Temperature Data:** The script tries multiple methods for temperature detection - Open Hardware Monitor, then Windows thermal zones. Some systems may not expose temperature sensors.
- **GPU Data:** GPU performance counters vary by system. The script will report if GPU monitoring is unavailable.
- **CPU Monitoring:** Uses real-time performance counters for accurate CPU usage. Falls back to process CPU time if counters fail.
- **Visual Interface:** The script now shows progress bars, completion status, and clear instructions about where to find log files.
- **Customization:** Adjust `$monitorDuration` or `$interval` to change how long or how often the script checks.
- **Alternative Tools:** If you prefer HWMonitor or other tools, manually correlate their readings with the script's process logs.
