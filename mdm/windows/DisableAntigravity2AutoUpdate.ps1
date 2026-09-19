<#
.SYNOPSIS
    Enforces corporate version lock and disables auto-updates for Antigravity 2.0 via Windows Intune Proactive Remediation / PowerShell.
.DESCRIPTION
    1. Sets system-level machine environment variable AGY_CLI_DISABLE_AUTO_UPDATE=1.
    2. Adds a DNS sinkhole entry in C:\Windows\System32\drivers\etc\hosts for the auto-updater endpoint.
#>

# 1. Enforce System-wide Environment Variable
$EnvVarName = "AGY_CLI_DISABLE_AUTO_UPDATE"
$Target = [System.EnvironmentVariableTarget]::Machine

$CurrentVal = [System.Environment]::GetEnvironmentVariable($EnvVarName, $Target)
if ($CurrentVal -ne "1") {
    [System.Environment]::SetEnvironmentVariable($EnvVarName, "1", $Target)
    Write-Host "Set machine-level environment variable $EnvVarName=1"
} else {
    Write-Host "Environment variable $EnvVarName already set to 1."
}

# 2. Add DNS sinkhole entry in hosts file
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$Domain = "antigravity-cli-auto-updater-974169037036.us-central1.run.app"
$SinkholeEntry = "0.0.0.0 $Domain"

if (Test-Path $HostsPath) {
    $Content = Get-Content -Path $HostsPath
    if ($Content -notcontains $SinkholeEntry) {
        Add-Content -Path $HostsPath -Value "`n# Antigravity 2.0 Auto-Updater Sinkhole`n$SinkholeEntry" -Force
        Write-Host "Added DNS sinkhole for $Domain in $HostsPath"
    } else {
        Write-Host "DNS sinkhole entry already present in $HostsPath"
    }
} else {
    Write-Warning "Hosts file not found at $HostsPath"
}

Write-Host "Successfully applied Antigravity 2.0 lockdown policy."
exit 0
