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

# 3. Enforce Visual Studio Code Enterprise Update Lockdown (HKLM Registry Policy)
$VSCodePolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\VSCode"
if (!(Test-Path $VSCodePolicyKey)) {
    New-Item -Path $VSCodePolicyKey -Force | Out-Null
    Write-Host "Created registry key: $VSCodePolicyKey"
}
Set-ItemProperty -Path $VSCodePolicyKey -Name "UpdateMode" -Value "none" -Type String -Force
Set-ItemProperty -Path $VSCodePolicyKey -Name "ExtensionsAutoUpdate" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $VSCodePolicyKey -Name "ExtensionsAutoCheckUpdates" -Value 0 -Type DWord -Force
Write-Host "Applied VS Code GPO policies (UpdateMode=none, ExtensionsAutoUpdate=0)."

# 4. Enforce IntelliJ IDEA Platform Update Lockdown (idea64.exe.vmoptions)
$IntelliJDirs = Get-ChildItem -Path "C:\Program Files\JetBrains" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*IntelliJ*" }
foreach ($dir in $IntelliJDirs) {
    $vmOptionsPath = Join-Path $dir.FullName "bin\idea64.exe.vmoptions"
    if (Test-Path $vmOptionsPath) {
        $vmOptionsContent = Get-Content $vmOptionsPath
        if ($vmOptionsContent -notcontains "-Dide.no.platform.update=true") {
            Add-Content -Path $vmOptionsPath -Value "`n-Dide.no.platform.update=true" -Force
            Write-Host "Injected -Dide.no.platform.update=true into $vmOptionsPath"
        }
    }
}

Write-Host "Successfully applied Antigravity 2.0 and Host IDE lockdown policies."
exit 0
