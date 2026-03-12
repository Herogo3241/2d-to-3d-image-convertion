.\platform-tools\adb.exe push benchmark_model /data/local/tmp/

.\platform-tools\adb.exe push MiDaS.tflite /data/local/tmp/

.\platform-tools\adb.exe shell chmod +x /data/local/tmp/benchmark_model


# .\platform-tools\adb.exe shell /data/local/tmp/benchmark_model --graph=/data/local/tmp/MiDaS.tflite --num_threads=4



$log = .\platform-tools\adb.exe shell /data/local/tmp/benchmark_model --graph=/data/local/tmp/MiDaS.tflite --num_threads=4 2>&1 | Out-String
$deviceName = (.\platform-tools\adb.exe shell getprop ro.product.model).Trim()

$avg_us = [regex]::match($log, 'Inference \(avg\): (\d+)').Groups[1].Value
$min_us = [regex]::match($log, 'min=(\d+)').Groups[1].Value
$max_us = [regex]::match($log, 'max=(\d+)').Groups[1].Value
$memory = [regex]::match($log, 'overall=([\d.]+)').Groups[1].Value


[PSCustomObject]@{
    "Target Device"  = $deviceName
    "Threads"        = 4
    "Avg Latency"    = "$([math]::Round([double]$avg_us / 1000, 2)) ms"
    "Min Latency"    = "$([math]::Round([double]$min_us / 1000, 2)) ms"
    "Max Latency"    = "$([math]::Round([double]$max_us / 1000, 2)) ms"
    "Peak RAM Usage" = "$memory MB"
} | Format-Table -AutoSize