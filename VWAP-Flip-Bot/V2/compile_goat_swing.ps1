$ErrorActionPreference = "Stop"

$metaEditor = "C:\Program Files\Goat Funded MT5 Terminal\MetaEditor64.exe"
$sourceFile = Join-Path $PSScriptRoot "VWAP SWing bot.mq5"
$logFile    = Join-Path $PSScriptRoot "compile_goat_swing_cmd.log"

if(-not (Test-Path $metaEditor))
{
   throw "MetaEditor not found: $metaEditor"
}

if(-not (Test-Path $sourceFile))
{
   throw "Source file not found: $sourceFile"
}

Write-Host "Compiling with Goat Funded MetaEditor..."
Write-Host "Source: $sourceFile"
Write-Host "Log:    $logFile"

$args = @(
   "/compile:`"$sourceFile`"",
   "/log:`"$logFile`""
)

& $metaEditor @args | Out-Null

$deadline = (Get-Date).AddSeconds(20)
while(-not (Test-Path $logFile) -and (Get-Date) -lt $deadline)
{
   Start-Sleep -Milliseconds 500
}

if(-not (Test-Path $logFile))
{
   throw "Compile command ran, but no log was created at: $logFile"
}

Write-Host ""
Write-Host "Last compile log lines:"
Get-Content -Path $logFile -Tail 120
