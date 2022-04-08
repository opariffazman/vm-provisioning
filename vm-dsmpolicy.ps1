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

Write-Info "Registering Virtual Machine Trend Micro DSA"
& $Env:ProgramFiles"\Trend Micro\Deep Security Agent\dsa_control" -r | Out-Null
Start-Sleep -Milliseconds 122

Write-Info "Configuring Virtual Machine Trend Micro DSA Policy"
& $Env:ProgramFiles"\Trend Micro\Deep Security Agent\dsa_control" -a "policyid:31" | Out-Null
Start-Sleep -Milliseconds 122

Write-Info "Configuring Virtual Machine Trend Micro DSA Recommendation"
& $Env:ProgramFiles"\Trend Micro\Deep Security Agent\dsa_control" -m "RecommendationScan:true" | Out-Null
