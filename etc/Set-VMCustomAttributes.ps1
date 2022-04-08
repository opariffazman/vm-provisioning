Param (
  [Parameter(Mandatory = $true,ValueFromPipeline = $true)]
  $VM,
  $CostCenter,
  $CompletionDate,
  $Requester,
  $Custodian,
  $PSR,
  $ProjectName,
  $eCIRFNumber,
  $SRNumber,
  $Server
)

$VMS = Get-VM $VM

$VMS | ForEach-Object {
  $VMName = $_.Name
  if($CostCenter){ Set-Annotation -Entity $VMName -CustomAttribute 'Cost Center' -Value $CostCenter -Server $Server | Out-Null }
  if($CompletionDate){ Set-Annotation -Entity $VMName -CustomAttribute 'Completion Date' -Value $CompletionDate -Server $Server | Out-Null }
  else { Set-Annotation -Entity $VMName -CustomAttribute 'Completion Date' -Value (Get-date) -Server $Server | Out-Null}
  if($requester){ Set-Annotation -Entity $VMName -CustomAttribute 'Requester' -Value $requester -Server $Server | Out-Null }
  if($custodian){ Set-Annotation -Entity $VMName -CustomAttribute 'Custodian' -Value $custodian -Server $Server | Out-Null }
  if($PSR){ Set-Annotation -Entity $VMName -CustomAttribute 'PSR' -Value $PSR -Server $Server | Out-Null }
  if($ProjectName){ Set-Annotation -Entity $VMName -CustomAttribute 'Project Name' -Value $ProjectName -Server $Server | Out-Null }
  if($eCIRFNumber){ Set-Annotation -Entity $VMName -CustomAttribute 'eCIRF Number' -Value $eCIRFNumber -Server $Server | Out-Null }
  if($SRNumber){ Set-Annotation -Entity $VMName -CustomAttribute 'SR Number' -Value $SRNumber -Server $Server | Out-Null }
}
