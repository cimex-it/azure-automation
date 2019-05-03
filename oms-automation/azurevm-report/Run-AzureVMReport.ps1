
$WorkspaceId = Get-AutomationVariable -Name 'PingMonitorWorkspaceId'
$WorkspaceKey = Get-AutomationVariable -Name 'PingMonitorWorkspaceKey'
$LogType = 'AzureVMReport'

# Create the function to create the authorization signature
Function Build-Signature ($WorkspaceId, $WorkspaceKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($WorkspaceKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $WorkspaceId,$encodedHash
    return $authorization
}

# Create the function to create and post the request
Function Post-LogData($WorkspaceId, $WorkspaceKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -WorkspaceId $WorkspaceId `
        -WorkspaceKey $WorkspaceKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $WorkspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = "";
    }
	
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing -ErrorAction Continue
    return $response.StatusCode

}


$account = Get-AutomationConnection -Name AzureRunAsConnection
Login-AzAccount -ServicePrincipal -Tenant $account.TenantID -ApplicationId $account.ApplicationID -CertificateThumbprint $account.CertificateThumbprint -Environment "AzureCloud"

$vmList = Get-AzVM -Status

$report = @()
foreach ($vm in $vmList) {
  $reportVM = [ordered]@{
      Name = $null
      PowerState = $null
      CPUs = $null
      MemoryGB = $null
      OSDiskSizeGB = $null
      OSDiskType = $null
      DataDisk1SizeGB = $null
      DataDisk1Type = $null
      DataDisk2SizeGB = $null
      DataDisk2Type = $null
  }

  $reportVM.Name = $vm.Name
  $vmSize = $vm.HardwareProfile.VMSize
  $reportVM.PowerState = $vm.PowerState
  $vmResources = Get-AzVMSize -Location westeurope | where { $_.Name -eq $vmSize }
  $reportVM.CPUs = $vmResources.NumberOfCores
  $reportVM.MemoryGB = ($vmResources.MemoryInMB)/1024

  $osDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
  if ($osDiskSize -eq $null -and $vm.StorageProfile.OSDisk.ManagedDisk -ne $null) {
    $osdisk = get-azdisk -name $vm.storageprofile.osdisk.name
    $reportVM.OSDiskSizeGB = $osdisk.DiskSizeGB
  } else {
    $reportVM.OSDiskSizeGB = $vm.StorageProfile.OsDisk.DiskSizeGB
  }

  if ($vm.StorageProfile.OSDisk.ManagedDisk -ne $null) {
    $osdisk = get-azdisk -name $vm.storageprofile.osdisk.name
    $reportVM.OSDiskType = switch ($osDisk.Sku.Name) {
        "Standard_LRS" {"Standard HDD"}
        "StandardSSD_LRS" {"Standard SSD"}
        "Premium_LRS" {"Premium SSD"}
        $null {"Unknown"}
        default {"Unknown"}
    }
  } else {
    $reportVM.OSDiskType = "Unknown"
  }

  $dataDisks = $vm.StorageProfile.DataDisks
  $i = 1
  foreach ($dataDisk in $dataDisks) {
    $propSizeName = "DataDisk" + $i + "SizeGB"
    $dataDiskSize = $dataDisk.DiskSizeGB
    
    if ($dataDiskSize -eq $null -and $dataDisk.ManagedDisk -ne $null) {
        $dataManagedDisk = get-azdisk -name $vm.storageprofile.osdisk.name
        $reportVM.$propSizeName = $dataManagedDisk.DiskSizeGB
    } else {
        $reportVM.$propSizeName = $dataDiskSize
    }

    if ($dataDisk.ManagedDisk -eq $null) {
        $reportVM.$propTypeName = "Unknown"
    } else {
        $propTypeName = "DataDisk" + $i + "Type"
        $dataManagedDisk = get-azdisk -name $dataDisk.Name
        $reportVM.$propTypeName = switch ($dataManagedDisk.Sku.Name) {
            "Standard_LRS" {"Standard HDD"}
            "StandardSSD_LRS" {"Standard SSD"}
            "Premium_LRS" {"Premium SSD"}
            default {"Unknown"}
        }
    }
    $i++
  }

  $reportObj = New-Object -TypeName psobject -Property $reportVM
 

  $Data = $reportObj | ConvertTo-Json
    
  $EventProperties = [pscustomobject]@{Data=$Data}
  $EVENTDATA = [pscustomobject]@{EventProperties=$EventProperties}

  $json = "[$($EVENTDATA.EventProperties.Data)]"
  $body = ([System.Text.Encoding]::UTF8.GetBytes($json))
  
  $post = Post-LogData -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $logType

  if($post -eq 202 -or $post -eq 200){
      Write-output "Event written to $WorkspaceId"
  } else {
      Write-output "StatusCode: $post - failed to write to $WorkspaceId"
      Throw "StatusCode: $post - failed to write to $WorkspaceId"
  }

}