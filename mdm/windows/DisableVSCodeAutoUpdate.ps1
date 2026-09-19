<#
.SYNOPSIS
    Enforces corporate version lock for Antigravity-enabled editors via Windows Registry (Intune Proactive Remediation).
.DESCRIPTION
    Applies Machine-level group policies that disable background updates and grey out manual update checks.
#>

$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\VSCode"

# Create registry key if absent
if (-not (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
    Write-Host "Created registry key: $RegistryPath"
}

# 1. Disable client application updates
Set-ItemProperty -Path $RegistryPath -Name "UpdateMode" -Value "none" -Type String -Force

# 2. Disable automated extension check and update
Set-ItemProperty -Path $RegistryPath -Name "ExtensionsAutoCheckUpdates" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $RegistryPath -Name "ExtensionsAutoUpdate" -Value 0 -Type DWord -Force

Write-Host "Successfully applied machine-level Antigravity lockdown policies."
exit 0
