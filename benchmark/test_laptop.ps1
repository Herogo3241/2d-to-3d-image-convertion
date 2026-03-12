Write-Host "Running 50 iterations natively on Windows (Please wait a few seconds)..." -ForegroundColor Yellow

# Run the benchmark locally and capture the output
$log = .\benchmark_model_windows_x86_64.exe --graph=MiDaS.tflite --num_threads=4 2>&1 | Out-String

# Check if the run was successful using the new LiteRT log format
if ($log -match "Inference \(avg\)") {
    Write-Host "Benchmark complete! Formatting results..." -ForegroundColor Green
    
    # Extract the exact numbers using Regex tailored for the LiteRT format
    $avg_ms = [regex]::match($log, 'Inference \(avg\):\s+([\d.]+)\s+ms').Groups[1].Value
    $min_ms = [regex]::match($log, 'Inference \(min\):\s+([\d.]+)\s+ms').Groups[1].Value
    $max_ms = [regex]::match($log, 'Inference \(max\):\s+([\d.]+)\s+ms').Groups[1].Value
    $memory = [regex]::match($log, 'Overall footprint:\s+([\d.]+)\s+MB').Groups[1].Value

    # Grab your laptop's exact CPU model name dynamically
    $cpuName = (Get-CimInstance Win32_Processor).Name.Trim()

    # Build and print the clean table
    [PSCustomObject]@{
        "Target Device"  = $cpuName
        "Threads"        = 4
        "Avg Latency"    = "$avg_ms ms"
        "Min Latency"    = "$min_ms ms"
        "Max Latency"    = "$max_ms ms"
        "Peak RAM Usage" = "$memory MB"
    } | Format-Table -AutoSize
} else {
    Write-Host "Error: Benchmark failed to run. Here is the output:" -ForegroundColor Red
    Write-Output $log
}