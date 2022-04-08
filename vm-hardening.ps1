mode 300
function Write-Info {
  param ($Message)
  $time = $(Get-Date).ToString("dd-MM-yy h:mm:ss tt") + ''
  Write-Verbose -Message "$time $Message." -Verbose
}

function Write-Exception {
  param ($ExceptionItem)
  $exc = $exceptionItem
  $time = $(Get-Date).ToString("dd-MM-yy h:mm:ss tt") + ''
  if ($exc.Exception.ErrorCategory) {
    $item = $exc.Exception.ErrorCategory | Out-String
    $itemfixed = $item.Replace([environment]::NewLine , '')
    Write-Warning -Message "$time $itemfixed."
  }
  elseif ($exc.Exception) {
    $item = $exc.Exception | Out-String
    $itemfixed = $item.Replace([environment]::NewLine , '')
    Write-Warning -Message "$time $itemfixed."
  }
  else {
    $item = $exc | Out-String
    $itemfixed = $item.Replace([environment]::NewLine , '')
    Write-Warning -Message "$time $itemfixed."
  }
  Start-Sleep -Milliseconds 500
}

$jsonInfoPath = "$PSScriptRoot\jsonInfo.json"
$jsonInfo = Get-Content $jsonInfoPath -Raw | ConvertFrom-Json

$prodMacAdd = $jsonInfo.ProductionMacAddress
$dnsIP = $jsonInfo.DNS
$prodIP = $jsonInfo.ProductionIP
$prefix = $jsonInfo.Prefix
$defaultGateaway = $jsonInfo.DefaultGateway
$backMacAdd = $jsonInfo.BackupMacAddress
$backIP = $jsonInfo.BackupIP

if ("$prodMacAdd") {
  Write-Info "Renaming Virtual Machine Production Network Adapter"
  Get-NetAdapter | Where-Object MacAddress -eq $prodMacAdd | Rename-NetAdapter -NewName 'Production' | Out-Null

  Write-Info "Assigning Virtual Machine with DNS $dnsIP"
  Set-DnsClientServerAddress -InterfaceAlias 'Production' -ServerAddresses $dnsIP | Out-Null

  Write-Info "Disabling Virtual Machine IPv6 for Production IP"
  Disable-NetAdapterBinding -Name 'Production' -ComponentID ms_tcpip6 | Out-Null

  if ("$prodIP") {
    Write-Info "Assigning Virtual Machine with Production IP '$prodIP'"
    New-NetIPAddress -InterfaceAlias 'Production' -IPAddress $prodIP -AddressFamily IPv4 -PrefixLength $prefix -DefaultGateway $defaultGateaway | Out-Null

    $ipConfig = "ipconfig -all"
    if ($ipConfig -match 'Duplicate') {
      Write-Exception "Production IP '$prodIP' Conflict Detected"
      Remove-NetIPAddress -InterfaceAlias 'Production' -Confirm:$false | Out-Null
      Write-Info "Clearing Production IP Configuration"
    }
  }
  else {
    Write-Exception "No Production IP Specified"
  }
}
else { Write-Exception "No Production Network Adapter Specified" }

if ("$backMacAdd") {
  Write-Info "Renaming Virtual Machine Backup Network Adapter"
  Get-NetAdapter | Where-Object MacAddress -eq $backMacAdd | Rename-NetAdapter -NewName 'Backup' | Out-Null

  Write-Info "Disabling Virtual Machine IPv6 for Backup IP"
  Disable-NetAdapterBinding -Name Backup -ComponentID ms_tcpip6 | Out-Null

  Write-Info "Disabling Virtual Machine DNS Connection Address for Backup IP"
  Set-DnsClient -InterfaceAlias Backup -RegisterThisConnectionsAddress:$false | Out-Null

  if ("$backIP") {
    Write-Info "Assigning Virtual Machine with Backup IP $backIP"
    New-NetIPAddress -InterfaceAlias 'Backup' -IPAddress $backIP -AddressFamily IPv4 -PrefixLength 22 | Out-Null

    $ipConfig = "ipconfig -all"
    if ($ipConfig -match 'Duplicate') {
      Write-Exception "Backup IP '$backIP' Conflict Detected"
      Remove-NetIPAddress -InterfaceAlias 'Backup' -Confirm:$false | Out-Null
      Write-Info "Clearing Backup IP Configuration"
    }
  }
  else { Write-Exception "No Backup IP Specified" }
}

# Write-Info "Disabling Firewall Startup Services"
# REG add "HKLM\SYSTEM\CurrentControlSet\services\MpsSvc" /v Start /t REG_DWORD /d 2 /f | Out-Null
<#
0 = Boot
1 = System
2 = Automatic
3 = Manual
4 = Disabled
#>

Write-Info "Disabling Virtual Machine Firewall: Domain, Public, Private"
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False | Out-Null

# Write-Info "Self-Destructing Hardening Script from Virtual Machine in 3s"
# Start-Sleep -Seconds 3
# Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force
