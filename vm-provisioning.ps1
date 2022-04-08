<#
.SYNOPSIS
    This script automates the process of provisioning server as well as hardening.
.DESCRIPTION
    COD VM Provisioning part currently supports:
    - identify and automatically connects to vCenter
    - identify esx host with lowest memory usage on specified cluster
    - identify datastore with largest free space on specified cluster
    - create vm from manually sysprep-ed template from wintel (olan)
    - using oscustomizationspec to configure administrator account, time, etc
    - assign vCPU & vRAM accordingly
    - enable hot add functionality
    - automatically identify network adapter from ip provided
    - assign vNIC (production/backup) if any
    - assign additional disk(s) if any
    - generate a dynamic script for hardening the vm
    - update vmtools if needed
    - can be use against multiple vcenter
    - utilize custom attribute for virtual machine details

    COD VM Hardening part currently supports:
    - rename production/backup adapter if any
    - assign ip configuration accordingly if any
    - disable firewall services and policy
    - initialize & online RAW disk if any
    - currently only supports vDisk, no physical RDM yet
    - activate trend micro deep security agent

.NOTES
    File Name   : vm-provisioning.ps1
    Author      : ariff.azman
    Version     : 1.1
.LINK

.INPUTS
    COD vCenter information including credentials
    Comma seperated value .csv file that include vm details
.OUTPUTS
    VM provisioned & hardened according to .csv file
    Verbose logging transcript .log file
#>

# functions here
switch ($PSVersionTable.PSVersion.Major) {
  # powershell version switch
  '6' {
    function Write-Exception {
      param ($ExceptionItem)
      # Clear-Host
      $exc = $exceptionItem
      $time = $(Get-Date).ToString("dd-MM-yy h:mm:ss tt") + ''
      if ($exc.Exception.ErrorCategory) {
        $item = $exc.Exception.ErrorCategory | Out-String -NoNewline
        Write-Warning -Message "$time $item."
      }
      elseif ($exc.Exception) {
        $item = $exc.Exception | Out-String -NoNewline
        Write-Warning -Message "$time $item."
      }
      else {
        $item = $exc | Out-String -NoNewline
        Write-Warning -Message "$time $item."
      }
      Start-Sleep -Milliseconds 500
    }
  }
  '5' {
    function Write-Exception {
      param ($ExceptionItem)
      # Clear-Host
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
  }
}

function Write-Info {
  param ($Message)
  # Clear-Host
  $time = $(Get-Date).ToString("dd-MM-yy h:mm:ss tt") + ''
  Write-Verbose -Message "$time $Message." -Verbose
  Start-Sleep -Milliseconds 500
}

function Write-Header {
  Write-Output "--------------------------------"
  Write-Output "vm-provisioning-hardened.ps1`n"
  Write-Output "--------------------------------"
}
function EnableMemHotAdd($VM, $VIServer) {
  $vmview = Get-VM $VM -Server $VIServer | Get-view
  $vmConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
  $vmConfigSpec.MemoryHotAddEnabled = $true
  $vmview.ReconfigVM($vmConfigSpec)
}

function EnableCpuHotAdd($VM, $VIServer) {
  $vmview = Get-VM $VM -Server $VIServer | Get-view
  $vmConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
  $vmConfigSpec.CPUHotAddEnabled = $true
  $vmview.ReconfigVM($vmConfigSpec)
}
function FarmSwitch($farm, $prodIP) {
  [hashtable]$value = @{ }
  switch ($farm) {

  }
  return $value
}

function ExitScript {
  $ProgressPreference = $OriginalPref
  # Disconnect-VIServer * -Confirm:$false | Out-Null
  Stop-Transcript | Out-Null
  Write-Info "Transcript stopped, output file is $currTranscriptName"
  exit
}

# Initial Constant Variables ********************************************************************
if (Get-Module -Name 'VMWare.PowerCLI' -ListAvailable) {
  # continue
}else {
  Write-Exception -ExceptionItem "Required Module `"VMWare.PowerCLI`" Not Installed"
  Start-Process 'https://www.powershellgallery.com/packages/VMware.PowerCLI/'
  ExitScript
}

$vmListPath = Get-ChildItem "$PSScriptRoot\" -Filter *.csv | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$credPath = "$PSScriptRoot\guestCred.cred"
$keyPath = "$PSScriptRoot\key.txt"
$hardeningScriptPath = "$PSScriptRoot\vm-hardening.ps1"
$jsonInfoPath = "$PSScriptRoot\jsonInfo.json"
$DSMPolicyPath = "$PSScriptRoot\vm-dsmpolicy.ps1"
$currTranscriptName = "$PSScriptRoot\logs\transcript-vm-provisioned-$($(Get-Date).ToString(`"dd-MMM-yy H-mm`")).log"
$OriginalPref = $ProgressPreference # Default is 'Continue'
$ProgressPreference = "SilentlyContinue"

if (!(Test-Path $vmListPath)) {
  $listInfo = {} | Select-Object 'Farm', 'Folder', 'Name', 'Template', 'Cluster', 'VMHost', 'Tier', 'vCPU', 'vRAM', `
  'vDiskCount', 'DiskSize1', 'DiskSize2', 'DiskSize3', 'ProductionIP', 'BackupIP', 'ProductionNIC', 'BackupNIC', 'eCIRF Number', 'Project Name', 'PSR', `
  'Cost Center', 'Custodian', 'Requester', 'SRNumber'
  Write-Exception "Required file `"*.csv`" not found, initializing file, run the script again after required details are filled or downloaded from eCIRF website"
  $listInfo | Export-Csv -NoTypeInformation -Path "$PSScriptRoot\vm-provision-list.csv"

  Write-Info "eCIRF website link $link"
  $link = Read-Host -Prompt "Go to link?"

  switch ($link) {
    'Y' { Start-Process $link }
    'N' { exit }
    Default { exit }
  }

  exit
}else {
  # continue
}

Write-Info "Performing the operation `"Create Directory`" on target `"Destination: $PSScriptRoot\logs`""
try { New-Item -ItemType 'Directory' -Path "$PSScriptRoot\logs" -ErrorAction 'Stop' | Out-Null }
catch { Write-Exception -ExceptionItem $PSItem }

Write-Header

switch ($PSVersionTable.PSVersion.Major) {
  # powershell version switch
  '6' { Start-Transcript -Path $currTranscriptName -UseMinimalHeader -Append | Out-Null }
  '5' { Start-Transcript -Path $currTranscriptName -Append | Out-Null }
}
Write-Info "Transcript started, output file is $currTranscriptName"

Set-ExecutionPolicy -ExecutionPolicy 'RemoteSigned' -Scope 'CurrentUser' -Confirm:$false | Out-Null
Write-Info "Performing the operation `"Set-ExecutionPolicy`" on target `"RemoteSigned`""
Set-PowerCLIConfiguration -DefaultVIServerMode 'Multiple' -Scope 'Session' -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction 'Ignore' -Scope 'Session' -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 -Scope 'Session' -Confirm:$false | Out-Null
Write-Info "Performing the operation `"Update PowerCLI configuration`""

# Import .csv & .cred files  ********************************************************************
Write-Info "Performing the operation `"Import-(Clixml/Csv)`" on neccessary credential & .csv files"
echo "$vmListPath"
echo "$($vmListPath.FullName)"
try {
  $vmList = Import-CSV $vmListPath.FullName -UseCulture
  $guestCredRaw = Import-Clixml $credPath
  $key = Get-Content $keyPath
}
catch {
  Write-Exception -ExceptionItem $PSItem
  ExitScript
}

# decrypting guest credential, essential for all user to use the same key instead of their unique ones
try {
  Write-Info "Decrypting Guest Credential"
  $guestPass = ConvertTo-SecureString -String $guestCredRaw.Password -Key $key
  $guestCred = New-Object System.Management.Automation.PSCredential($guestCredRaw.UserName, $guestPass)
}
catch {
  Write-Exception -ExceptionItem $PSItem
  ExitScript
}

# Connect to each vCenter defined inside .csv  *****************************************************
$uniqueFarm = $vmList | Select-Object Farm -Unique
$uniqueFarm | ForEach-Object {
  $value = FarmSwitch -farm $_.Farm -prodIP $null
  try {
    Connect-VIServer -Server $value.viServer `
      -Credential (Get-Credential -Message 'Provide "\a-" Credential') `
      -ErrorAction 'Stop' | Out-Null
    Write-Info "Establishing connection to $($_.Farm) Server suceeded: $($value.viServer)"
  }
  catch {
    Write-Exception -ExceptionItem $PSItem
    ExitScript
  }
}

# Loop for each VM in .csv *******************************************************************
$vmCount = 1
$vmList | ForEach-Object {
  # VM Required Attributes Here **************************************************************
  $vm = $_
  $farm = $vm.Farm
  $VMName = $vm.Name
  $Template = $vm.Template
  $Cluster = $vm.Cluster
  $TierPath = $vm.Tier
  $vCPU = $vm.vCPU
  $vRAM = $vm.vRAM

  # due to BDC PQZ using different datacenter hence, need to use their own templates
  if($farm -eq 'CISCO UCS PQZ'){
    $Template = $Template + '_PQZ'
  }

  if (!$VMName) {
    Write-Exception "VM Name Not specified"
    ExitScript
  }elseif (!$Template) {
    Write-Exception "Template Not Specified"
    ExitScript
  }elseif (!$Cluster) {
    Write-Exception "Cluster Not Specified"
    ExitScript
  }elseif (!$TierPath) {
    Write-Exception "Tier Not Specified"
    ExitScript
  }elseif (!$vCPU) {
    Write-Exception "vRAM Not Specified"
    ExitScript
  }elseif (!$vRAM) {
    Write-Exception "vRAM Not Specified"
    ExitScript
  }

  # VM Optional Attributes Here **************************************************************
  $Folder = $vm.Folder
  $vHost = $vm.VMHost
  $vDatastore = $vm.Datastore
  $vDiskCount = $vm.vDiskCount
  $prodIP = $vm.ProductionIP
  $backIP = $vm.BackupIP
  $prodNIC = $vm.ProductionNIC # for special cases where naming convention is not reliable
  $backNIC = $vm.BackupNIC         # need to use the Production/Backup Network Card from .csv instead

  # VM Auto-assign Attributes Here ************************************************************
  $vNICProd = if ($prodIP -and !$prodNIC) { "10{2}" -f ($prodIP.Split(".")) } else { $prodNIC }
  $vNICBack = if ($backIP -and !$backNIC) { "1{2}" -f ($backIP.Split(".")) } else { $backNIC } # backup IP usually 10.xx.xxx.x

  # vCenter Server variable
  $value = FarmSwitch -farm $farm -prodIP $null

  if (!(Get-VM $VMName -Server $value.viServer -ErrorAction 'SilentlyContinue')) { # SilentlyContinue so it doesn't mess up the terminal with error
    Write-Output "[`"$VMName`"] [$vmCount]"
    Write-Info "Provisioning Task [$vmCount] for `"$VMName`" Started"
    # ESXi Host Auto-assign Here ************************************************************
    $i = 0 # index counter
    if ($vHost) {
      $VMHost = $vHost
    }else{
      do {
        Write-Info "Identifying most preferable ESX Host for `"$VMName`""
        $VMHostTemp = Get-Cluster $Cluster -Server $value.viServer | Get-VMHost -State Connected | `
          Sort-Object -Property MemoryUsageGB | `
          Sort-Object -Property Version -Descending | Select-Object -Index $i
        $hostTriggered = Get-VMHost $VMHostTemp | Get-View | Where-Object TriggeredAlarmState -ne $null

        # Ensure ESXi Host doesn't have any critical alarms
        if ($hostTriggered) {
          Write-Exception "ESX Host `"$VMHostTemp`" Triggered Alarm"
          foreach ($triggered in $hostTriggered.TriggeredAlarmState) {
            if ($triggered.OverallStatus -like "red" ) {
              Write-Exception "ESX Host `"$VMHostTemp`" Triggered Red Alarm"
              $VMHost = $null
              $i++
            }
            else { $VMHost = $VMHostTemp }
          }
        }
        else { $VMHost = $VMHostTemp }
      }until ($VMHost)
    }

    Write-Info "Preferred ESX Host Identified: `"$VMHost`""

    # Check Datastore Tier Type from .csv *******************************************************
    switch ($TierPath) {
      'Super High Performance' { $Tier = 'T1' } # Not exactly sure if it even exists
      'High Performance' { $Tier = 'T2' }
      'Performance' { $Tier = 'T3' }
      'Standard' { $Tier = 'T4' }
    }

    # Datastore Auto-assign Here *****************************************************************
    $i = 0 # index counter
    if ($vDatastore) {
      $LargestDatastore = $vDatastore
    }
    else {
      do {
        Write-Info "Identifying most preferable Datastore for `"$VMName`""
        $DatastoreTemp = (Get-VMHost $VMHost -Server $value.viServer | Get-Datastore | Select-Object Name, `
          @{ N = "Tag"; E = { Get-TagAssignment -Entity $_ | Select-Object -ExpandProperty Tag } }, FreeSpaceGB | `
            Where-Object { # Adjust here to fit most environment
            $_.Name -match $Tier -and # Datastore Tier
            $_.State -ne 'Unavailable' -and # Datastore State
            $_.Tag.Name -notcontains 'Dedicated'      # Datastore Tag
          } | Sort-Object -Property FreeSpaceGB -Descending | Select-Object -Index $i).Name
        $dsTriggered = Get-Datastore $DatastoreTemp | Get-View | Where-Object TriggeredAlarmState -ne $null

        # Ensure Datastore doesn't have any critical alarms
        if ($dsTriggered) {
          Write-Exception "Datastore `"$DatastoreTemp`" Triggered Alarm"
          foreach ($triggered in $dsTriggered.TriggeredAlarmState) {
            if ($triggered.OverallStatus -like "red" ) {
              Write-Exception "Datastore `"$DatastoreTemp`" Triggered Red Alarm"
              $LargestDatastore = $null
              $i++
            }
            else { $LargestDatastore = $DatastoreTemp }
          }
        }
        else { $LargestDatastore = $DatastoreTemp }
      } until ($LargestDatastore)
    }

    Write-Info "Preferred Datastore Identified: `"$LargestDatastore`""

    if((Get-Template $Template).Extensiondata.Config.GuestFullName -match 'Linux'){
      # Build Clone VM Info *********************************************************************
      $cloneInfo = @{
        VM                  = $Template
        Name                = $VMName
        VMHost              = $VMHost
        Datastore           = $LargestDatastore
        DiskStorageFormat   = "Thin"
        ErrorAction         = "Stop"
        Server              = $value.viServer
      }
    }elseif((Get-Template $Template).Extensiondata.Config.GuestFullName -match 'Windows'){
      $cloneInfo = @{
        Template            = $Template
        Name                = $VMName
        VMHost              = $VMHost
        Datastore           = $LargestDatastore
        DiskStorageFormat   = "Thin"
        OSCustomizationSpec = 'WINOSCustomSpec'
        ErrorAction         = "Stop"
        Server              = $value.viServer
      }
    }
    else{
      Write-Exception "Template Not Supported"
    }

    # VM Creation from Template Starts Here ***************************************************
    Write-Info "Creating New Virtual Machine `"$VMName`" from Template `"$Template`""
    try {  New-VM @cloneInfo | Out-Null }
    catch {
      Write-Exception -ExceptionItem $PSItem
      return
    }

    # Folder Creation Starts Here *************************************************************
    if ($Folder) {
      if (!(Get-Folder $Folder -Server $value.viServer -ErrorAction 'SilentlyContinue')) {
        Write-Info "Creating Folder `"$Folder`""
        switch ($farm) { # This switch is due to how different folder structure been made for different farms
          'CISCO UCS' {
            try { Get-Folder 'ICT' -Server $value.viServer | New-Folder $Folder -ErrorAction 'Stop' | Out-Null }
            catch { Write-Exception -ExceptionItem $PSItem }
          }
          'DR Common SAP' {
            try { (Get-Folder -Name VM -Server $value.viServer )[1] | New-Folder $Folder -ErrorAction 'Stop' | Out-Null }
            catch { Write-Exception -ExceptionItem $PSItem }
          }
          Default {
            try { (Get-Folder -Name VM -Server $value.viServer )[0] | New-Folder $Folder -ErrorAction 'Stop' | Out-Null }
            catch { Write-Exception -ExceptionItem $PSItem }
          }
        }
      }
      else { Write-Info "Folder `"$Folder`" Already Exists" }
    }

    Write-Info "Moving Virtual Machine `"$VMName`" into Folder `"$Folder`""
    try { Move-VM -VM $VMName -Server $value.viServer -InventoryLocation (Get-Folder $Folder -Server $value.viServer) -ErrorAction 'Stop' | Out-Null }
    catch { Write-Exception -ExceptionItem $PSItem }

    # Assign Production Network Adapter if defined *************************************************
    if($vNICProd){
      if ($vNICProd -ne 'VM Network') { # the default network adapter being used for other farm than CISCO UCS usually
        try { # production network adapter usually contains "app/dev/web/db"
          $PortGroupProd = Get-VMHost $VMHost -Server $value.viServer | Get-VDSwitch | Get-VDPortgroup -ErrorAction 'Stop' | `
          Where-Object { $_.Name -Match "app|dev|web|db" -and $_.Name -match $vNICProd } | Select-Object -First 1
        }
        catch { Write-Exception -ExceptionItem $PSItem }
        # Build Production vNIC Info *****************************************************************
        $vNICProdInfo = @{
          VM             = $VMName
          Portgroup      = $PortGroupProd
          WakeOnLan      = $true
          StartConnected = $true
          Type           = "Vmxnet3"
          Confirm        = $false
          ErrorAction    = "Stop"
          Server         = $value.viServer
        }
        try {
          New-NetworkAdapter @vNICProdInfo | Out-Null
          Write-Info "Configuring `"$VMName`" Production Network Adapter `"$($PortGroupProd.Name)`""
        }
        catch { Write-Exception -ExceptionItem $PSItem }
      } elseif ($vNICProd -eq 'VM Network') {
        # Build Production vNIC Info *****************************************************************
        $vNICProdInfo = @{
          VM             = $VMName
          NetworkName      = $vNICProd
          WakeOnLan      = $true
          StartConnected = $true
          Type           = "Vmxnet3"
          Confirm        = $false
          ErrorAction    = "Stop"
          Server         = $value.viServer
        }
        try {
          New-NetworkAdapter @vNICProdInfo | Out-Null
          Write-Info "Configuring `"$VMName`" Production Network Adapter `"$vNICProd`""
        }
        catch { Write-Exception -ExceptionItem $PSItem }
      }
    }else { Write-Exception "No Production Network Adapter Specified" }

    # Assign Backup Network Adapter if defined *************************************************
    if ($vNICBack) {
      if ($vNICBack -ne 'Backup Network') {
        try { # backup network adapter usually contains "bkp"
          $PortGroupBack = Get-VMHost $VMHost -Server $value.viServer | Get-VDSwitch | Get-VDPortgroup -ErrorAction 'Stop' | `
          Where-Object { $_.Name -Match "bkp" -and $_.Name -match $vNICBack } | Select-Object -First 1
        }
        catch { Write-Exception -ExceptionItem $PSItem }
        # Build Backup vNIC Info *****************************************************************
        $vNICBackInfo = @{
          VM             = $VMName
          Portgroup      = $PortGroupBack
          WakeOnLan      = $true
          StartConnected = $true
          Type           = "Vmxnet3"
          Confirm        = $false
          ErrorAction    = "Stop"
          Server         = $value.viServer
        }
        try {
          New-NetworkAdapter @vNICBackInfo | Out-Null
          Write-Info "Configuring `"$VMName`" Backup Network Adapter `"$($PortGroupBack.Name)`""
        }
        catch { Write-Exception -ExceptionItem $PSItem }
      } elseif ($vNICBack -eq 'Backup Network') {
        # Build Production vNIC Info *****************************************************************
        $vNICProdInfo = @{
          VM             = $VMName
          NetworkName      = $vNICBack
          WakeOnLan      = $true
          StartConnected = $true
          Type           = "Vmxnet3"
          Confirm        = $false
          ErrorAction    = "Stop"
          Server         = $value.viServer
        }
        try {
          New-NetworkAdapter @vNICProdInfo | Out-Null
          Write-Info "Configuring `"$VMName`" Backup Network Adapter `"$vNICBack`""
        }
        catch { Write-Exception -ExceptionItem $PSItem }
      }
    }
    else { Write-Exception "No Backup Network Adapter Specified" }

    # Build VM Specifications ******************************************************************
    $vmSpec = @{
      VM          = $VMName
      NumCpu      = $vCPU
      MemoryGB    = $vRAM
      Confirm     = $false
      ErrorAction = "Stop"
      Server      = $value.viServer
    }
    # VM Memory and Cpu Configurations Starts Here *********************************************
    Write-Info "Configuring `"$VMName`" with `"$vCPU`" Virtual CPU & `"$vRAM`" GB Virtual Memory"
    try { Set-VM @vmSpec | Out-Null }
    catch { Write-Exception -ExceptionItem $PSItem }

    # VM Memory & Cpu Hotplug Enabled Here *****************************************************
    Write-Info "Enabling `"$VMName`" Hot Add vCPU"
    EnableCpuHotAdd -VM $VMName -VIServer $value.viServer
    Write-Info "Enabling `"$VMName`" Hot Add vRAM"
    EnableMemHotAdd -VM $VMName -VIServer $value.viServer

    # VM Additional Hard Disk if defined from csv **********************************************
    if ($vDiskCount -And $vDiskCount -gt 0) {
      Write-Info "Additional $vDiskCount vDisk(s) Required for `"$VMName`""
      $i = 1
      while ($i -le $vDiskCount) {
        $vDiskString = 'DiskSize' + $i
        $vDiskSize = $vm.$vDiskString
        Write-Info "Configuring `"$VMName`" with Additional Disk $i `"[$vDiskSize GB]`""
        Start-Sleep -Seconds 1
        $newDiskInfo = @{
          VM            = $VMName
          DiskType      = "Flat"
          CapacityGB    = $vDiskSize
          StorageFormat = "Thin"
          ErrorAction   = "Stop"
          Server        = $value.viServer
        }
        try { New-HardDisk @newDiskInfo | Out-Null }
        catch { Write-Exception -ExceptionItem $PSItem }
        $i++
      }
    }

    # VM Starts Powering On Here ****************************************************************
    Write-Info "Starting Virtual Machine `"$VMName`""
    try { Start-VM -VM $VMName -Server $value.viServer -ErrorAction 'Stop' | Out-Null }
    catch { Write-Exception -ExceptionItem $PSItem }

    Write-Info "Virtual Machine `"$VMName`" provisioned. Provisioning Task [$vmCount] Completed"
  }
  else { Write-Exception "Virtual Machine `"$VMName`" Already Exists" }
  $vmCount++
}

$vmCount = 1 # reset counter for hardening
$vmList | ForEach-Object {
  # VM Required Attributes Here **************************************************************
  $vm = $_
  $farm = $vm.Farm
  $VMName = $vm.Name
  $Template = $vm.Template

  # VM Optional Attributes Here **************************************************************
  $vDiskCount = $vm.vDiskCount
  $prodIP = $vm.ProductionIP
  $backIP = $vm.BackupIP
  $prodNIC = $vm.ProductionNIC     # for special cases where naming convention is not reliable
  $backNIC = $vm.BackupNIC             # need to use the Production/Backup Network Card from .csv instead

  # VM Auto-assign Attributes Here ************************************************************
  $vNICProd = if ($prodIP -and !$prodNIC) { "{2}" -f ($prodIP.Split(".")) } else { $prodNIC }
  $vNICBack = if ($backIP -and !$backNIC) { "{2}" -f ($backIP.Split(".")) } else { $backNIC }

  # vCenter Server variable
  $value = FarmSwitch -farm $farm -prodIP $null

  # Custom Attributes Here ********************************************************************
  $custAttInfo = @{
    VM             = $VMName
    eCIRFNumber    = $vm."eCIRF Number"
    ProjectName    = $vm."Project Name"
    PSR            = $vm."PSR"
    CostCenter     = $vm."Cost Center"
    Custodian      = $vm."Custodian"
    Requester      = $vm."Requester"
    SrNumber       = $vm."SR Number"
    Server         = $value.viServer
  }

  # VM Custom Attributes Assigned Here *********************************************************
  Write-Info "Setting Virtual Machine `"$VMName`" Annotation Value"
  try {
    & "$PSScriptRoot\etc\Set-VMCustomAttributes.ps1" @custAttInfo
  }
  catch {
    Write-Exception -ExceptionItem $PSItem
  }

  if (!(Get-VM $VMName -Server $value.viServer -ErrorAction 'SilentlyContinue')) {
    Write-Exception "Virtual Machine `"$VMName`" Not Found"
  }
  elseif((Get-Template $Template).Extensiondata.Config.GuestFullName -match 'Windows') {
    Write-Output "[`"$VMName`"] [$vmCount]"
    Write-Info "Hardening Task [$vmCount] for `"$VMName`" Started"
    # Due to how OSCustomizationSpec works, need to wait until it finishes executing its scripts & reboot a couple times until it actually finished

    # VM OS Customization and GuestOperation Completion ****************************************
    Write-Info "Waiting for `"$VMName`" Operating System Customization to Complete"
    do {
      $customizationSucceeded = Get-VIEvent -Entity $VMName -Server $value.viServer | Where-Object { $_.GetType().Name -eq "CustomizationSucceeded" }
      if ($customizationSucceeded) {
        $eventTime = ($customizationSucceeded.CreatedTime).ToString("h:mm:ss tt")
        $eventMessage = $customizationSucceeded.FullFormattedMessage
        Write-Info "$eventMessage [$eventTime]"
      }
      else { Start-Sleep -Seconds 3 }
    } until ($customizationSucceeded)

    Write-Info "Waiting for `"$VMName`" Guest Operations to Ready"
    do {
      try {
        $vm = Get-VM -Name $VMName -Server $value.viServer -ErrorAction Stop
        $vmToolsGuestOperationReady = $vm.ExtensionData.Guest.GuestOperationsReady
      }
      catch { Write-Exception -ExceptionItem $PSItem }
      if ($vmToolsGuestOperationReady) {
        Write-Info "Verifying `"$VMName`" VMWare Tools Agent Contactable"

        $verifyInfo = @{
          VM              = $VMName
          ScriptText      = "return $true"
          ScriptType      = "Powershell"
          GuestCredential = $guestCred
          ErrorAction     = "Stop"
          WarningAction   = "SilentlyContinue"
          Server          = $value.viServer
        }

        # try contacting VM tools agent just to be sure
        try { $verifyOutput = Invoke-VMScript @verifyInfo }
        catch{ Write-Exception -ExceptionItem $PSItem }
      }
      else {
        Start-Sleep -Seconds 1
        $vm.ExtensionData.UpdateViewData()
      }
    } until ($vmToolsGuestOperationReady -and $verifyOutput.ScriptOutput)


    # VM Production Network Adapter Assignation Here if defined ***********************************
    if ($vNICProd) {
      try { $prodMacAddRaw = Get-NetworkAdapter -VM $VMName -Server $value.viServer | Where-Object NetworkName -Match $vNICProd -ErrorAction 'Stop' }
      catch { Write-Exception -ExceptionItem $PSItem }

      # Build IP Configuration Info for Production Network Adapter if defined *********************
      $prodMacAdd = $prodMacAddRaw.MacAddress.Replace(":", "-")
      if ($prodIP) {
        $ipInfo = FarmSwitch -farm $farm -prodIP $prodIP
        $defaultGateaway = $ipInfo.defaultGateaway
        $dnsIP = $ipInfo.dnsIP
        $prefix = $ipInfo.prefix
        Write-Info "Defining Virtual Machine `"$VMName`" Production IP Configuration: $prodIP/$prefix"
      }
      else {
        $prodMacAdd = $null
        Write-Exception "Skipping Virtual Machine `"$VMName`" Production IP Configuration"
      }
    }

    # VM Backup Network Adapter Assignation Here if defined ***********************************
    if ($vNICBack) {
      try { $backMacAddRaw = Get-NetworkAdapter -VM $VMName -Server $value.viServer | Where-Object NetworkName -Match $vNICBack -ErrorAction 'Stop' }
      catch { Write-Exception -ExceptionItem $PSItem }
      $backMacAdd = $backMacAddRaw.MacAddress.Replace(":", "-")
      if ($backIP) {
        Write-Info "Defining Virtual Machine `"$VMName`" Backup IP Configuration: $backIP"
      }
      else {
        $backMacAdd = $null
        Write-Exception "Skipping Virtual Machine `"$VMName`" Backup IP Configuration"
      }
    }

    # Build Hardening Information to be sent to VM ********************************************
    Write-Info "Generating Virtual Machine Hardening Info for `"$VMName`""

    $jsonInfo = {} | Select-Object ProductionMacAddress, ProductionIP, Prefix, DefaultGateway, DNS, BackupMacAddress, BackupIP
    $jsonInfo.ProductionMacAddress = $prodMacAdd
    $jsonInfo.ProductionIP = $prodIP
    $jsonInfo.Prefix = $prefix
    $jsonInfo.DefaultGateway = $defaultGateaway
    $jsonInfo.DNS = $dnsIP
    $jsonInfo.BackupMacAddress = $backMacAdd
    $jsonInfo.BackupIP = $backIP

    $jsonInfo | ConvertTo-Json | Out-File $jsonInfoPath

    $copyJsonInfo = @{
      VM              = $VMName
      Source          = $jsonInfoPath
      Destination     = "C:\Users\Administrator\Desktop"
      LocalToGuest    = $true
      GuestCredential = $guestCred
      ErrorAction     = "Stop"
      WarningAction   = "SilentlyContinue"
      Server          = $value.viServer
    }

    Write-Info "Sending Virtual Machine Hardening Info to `"$VMName`""
    try { Copy-VMGuestFile @copyJsonInfo | Out-Null }
    catch { Write-Exception -ExceptionItem $PSItem }

    # Information for Sending the Hardening Script to VM **************************************
    $copyHardenInfo = @{
      VM              = $VMName
      Source          = $hardeningScriptPath
      Destination     = "C:\Users\Administrator\Desktop"
      LocalToGuest    = $true
      GuestCredential = $guestCred
      ErrorAction     = "Stop"
      WarningAction   = "SilentlyContinue"
      Server          = $value.viServer
    }

    Write-Info "Sending Virtual Machine Hardening Script to `"$VMName`""
    try { Copy-VMGuestFile @copyHardenInfo | Out-Null }
    catch { Write-Exception -ExceptionItem $PSItem }

    # Information for Invoking the Hardening Script at VM *************************************
    $invokeHardenInfo = @{
      VM              = $VMName
      ScriptType      = "Powershell"
      ScriptText      = "C:\Users\Administrator\Desktop\vm-hardening.ps1"
      GuestCredential = $guestCred
      ErrorAction     = "Stop"
      WarningAction   = "SilentlyContinue"
      Server          = $value.viServer
    }

    Write-Info "Invoking Virtual Machine Hardening Script at `"$VMName`""
    try { $hardenOutput = Invoke-VMScript @invokeHardenInfo }
    catch { Write-Exception -ExceptionItem $PSItem }

    # Information for Sending the Anti-Virus DSM Policy to VM *********************************
    $copyAVInfo = @{
      VM              = $VMName
      Source          = $DSMPolicyPath
      Destination     = "C:\Users\Administrator\Desktop"
      LocalToGuest    = $true
      GuestCredential = $guestCred
      ErrorAction     = "Stop"
      WarningAction   = "SilentlyContinue"
      Server          = $value.viServer
    }

    Write-Info "Sending Virtual Machine Anti-Virus DSM Policy to `"$VMName`""
    try { Copy-VMGuestFile @copyAVInfo | Out-Null }
    catch { Write-Exception -ExceptionItem $PSItem }

    # Information for Invoking the Anti-Virus DSM Policy at VM *******************************
    $invokeAVInfo = @{
      VM              = $VMName
      ScriptType      = "Powershell"
      ScriptText      = "C:\Users\Administrator\Desktop\vm-dsmpolicy.ps1"
      GuestCredential = $guestCred
      ErrorAction     = "Stop"
      WarningAction   = "SilentlyContinue"
      Server          = $value.viServer
      RunAsync        = $true
      # using runasync here in to implement timeout features if too long
    }

    if ($prodIP) {
      Write-Info "Invoking Virtual Machine DSM Policy at `"$VMName`""
      try { $AVOutput = Invoke-VMScript @invokeAVInfo }
      catch { Write-Exception -ExceptionItem $PSItem }

      $timeout = 15 ## seconds
      $timer = [Diagnostics.Stopwatch]::StartNew()
      Write-Info "15 seconds until Hardening Script at `"$VMName`" Timeout"
      while ($timer.Elapsed.TotalSeconds -lt $timeout) {
        if (($AVOutput.State) -match 'Success') {
          $timer.Stop()
          break
        }
        else {
          Start-Sleep -Milliseconds 400
        }
      }
      $timer.Stop()
    }

    # Initialize and Online defined additional Harddisk on VM *********************************
    if ($vDiskCount -And $vDiskCount -gt 0) {
      $scriptText = [scriptblock]::Create( {
          Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Initialize-Disk -PartitionStyle GPT -PassThru -Verbose | `
            New-Partition -UseMaximumSize -AssignDriveLetter -Verbose | Format-Volume -FileSystem NTFS -Confirm:$false -Verbose | Out-Null
        })

      # Information for Invoking the Disk Script at VM *************************************
      $invokeInfoDisk = @{
        VM              = $VMName
        ScriptType      = "Powershell"
        ScriptText      = $scriptText
        GuestCredential = $guestCred
        ErrorAction     = "Stop"
        Server          = $value.viServer
      }

      Write-Info "Initializing & Formatting Virtual Machine RAW Disk(s)"
      try { $diskOutput = Invoke-VMScript @invokeInfoDisk }
      catch { Write-Exception -ExceptionItem $PSItem }

      Write-Output "[`"$VMName`"] [$vmCount] [ScriptOutput]"
      $diskOutput.ScriptOutput
    }

    if ($timer.Elapsed.TotalSeconds -gt $timeout) {
      Write-Exception "Virtual Machine `"$VMName`" DSM Policy Timeout, Require Manual Override"
    }
    else {
      Write-Output "[`"$VMName`"] [$vmCount] [ScriptOutput]"
      $hardenOutput.ScriptOutput
      $AVOutput.Result.ScriptOutput
    }
    Write-Info "Virtual Machine `"$VMName`" hardened. Hardened Task [$vmCount] Completed"

    $vmToolsUpdateInfo = @{
      VM       = $VMName
      Server   = $value.viServer
      RunAsync = $true
    }

    Write-Info "Verifying `"$VMName`" VMWare Tools Version Status"
    try { $vmToolsVersion = (Get-View (Get-VM $VMName -Server $value.viServer -ErrorAction 'Stop')).Guest.ToolsVersionStatus }
    catch { Write-Exception -ExceptionItem $PSItem }
    if ($vmToolsVersion -eq 'guestToolsCurrent') {
      Write-Info "`"$VMName`" VMWare Tools Version Running Latest"
    }
    else {
      Write-Exception "`"$VMName`" VMWare Tools Version Outdated"
      Write-Info "Updating `"$VMName`" VMWare Tools & Reboot"
      try { Update-Tools @vmToolsUpdateInfo | Out-Null }
      catch { Write-Exception -ExceptionItem $PSItem }
    }
  }
  elseif ((Get-Template $Template).Extensiondata.Config.GuestFullName -match 'Linux') {
    Write-Info "Virtual Machine `"$VMName`" OS Linux, Skipping Hardening"
  }else {
    Write-Exception "Template Not Supported"
  }
  $vmCount++
}

$vmDetails = $vmlist | ForEach-Object {
  Get-VMGuest -VM $_.Name | Select-Object HostName, IPAddress
}

$vmDetailsParsed = $vmDetails | ForEach-Object {
  $_.HostName + ' ' + $_.IPAddress + '%0A'
}

# Build JoinAPI URL ********************************************************************************
# to invoke-webrequest for sending notification of script completion to android
$ExecutionBy = "$env:UserName@$env:UserDomain%20$env:ComputerName"
$ScriptDetails = "$($MyInvocation.InvocationName)%0A$ExecutionBy%0A$vmDetailsParsed"

$joinURL = "https://joinjoaomgcd.appspot.com/_ah/api/messaging/v1/sendPush?text=$ScriptDetails&title=Script%20Execution%20Completed&icon=https%3A%2F%2Fupload.wikimedia.org%2Fwikipedia%2Fcommons%2F0%2F01%2FWindows_Terminal_Logo_256x256.png&smallicon=https%3A%2F%2Fcdn0.iconfinder.com%2Fdata%2Ficons%2Focticons%2F1024%2Fterminal-512.png&deviceId=9f08b54813fa4c92857fd63080766c09&apikey=1a6ca440fb3447bc983f7c7cb8257a03"

Invoke-WebRequest -Uri $joinURL | Out-Null
# *************************************************************************************************

ExitScript
