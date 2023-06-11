# Connecting to Azure Parameters
$tenantID = "d97407c7-22d2-4ee5-912b-fa3d04e5e9e5"
$applicationID = "27c76eed-c929-486f-a37b-cc3e0313d3a1"
$clientKey = Get-AutomationVariable "VisionLineBackupSecret"
$tenantName = "cimex"
$automationVariableName = "VisionlineBackupConfig"
$dateFormat = "yyyy_MM_dd"

$backupConfigJson = (Get-AutomationVariable $automationVariableName).Replace('\', '\\')
$backupConfig = $backupConfigJson | ConvertFrom-Json

$siteServerRelativeUrl = $backupConfig.siteServerRelativeUrl
$libraryName = $backupConfig.libraryName
$sharePointRelativeFolderPath = $backupConfig.sharePointRelativeFolderPath
$uploadFiles = $backupConfig.files

function Get-GraphAccessToken {
  [CmdletBinding()]
  param (
      $TenantId,
      $ApplicationId,
      $ClientKey
  )

  $url = "https://login.microsoftonline.com/$tenantId/oauth2/token"
  $resource = "https://graph.microsoft.com/"
  $restbody = @{
    grant_type    = 'client_credentials'
    client_id     = $applicationID
    client_secret = $clientKey
    resource      = $resource
  }

  # Get the return Auth Token
  $token = Invoke-RestMethod -Method POST -Uri $url -Body $restbody
  
  return $token
}


function Upload-SharepointFile {
  [CmdletBinding()]
  param (
      $AccessToken,
      $SiteServerRelativeUrl,
      $TenantName,
      $LibraryName,
      $SharePointRelativeFolderPath,
      $AlternativeFileName,
      $PathFileToUpload
  )

    # Set the baseurl to MS Graph-API (BETA API)
  $baseUrl = 'https://graph.microsoft.com'
          
  # Pack the token into a header for future API calls
  $header = @{
    'Authorization' = "$($AccessToken.token_type) $($AccessToken.access_token)"
    'Content-type'  = "application/json"
  }

  Write-Output "Getting Site ID for $SiteServerRelativeUrl..."
  $siteIdUrl = "https://graph.microsoft.com/v1.0/sites/$TenantName.sharepoint.com:$($SiteServerRelativeUrl)?`$select=id"
  $siteId = (Invoke-RestMethod -Method GET -headers $header -Uri $siteIdUrl).id

  Write-Output "Getting Drive ID for the Library:$LibraryName..."
  $driveIdUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/drives?`$select=id,name"
  $driveId = $((Invoke-RestMethod -Method GET -headers $header -Uri $driveIdUrl).value | Where-Object { $_.name -eq $LibraryName }).id

  Write-Output "Getting Library Path and Name..."
  if ($AlternativeFileName) {
      $name = $AlternativeFileName
  } else {
      $Path = $PathFileToUpload.Replace('\', '/')
      $name = $Path.Substring($Path.LastIndexOf("/") + 1)
  }

  $uploadPath = $SharePointRelativeFolderPath + "/$name"
  if (-not $uploadPath.StartsWith('/')) {
      $uploadPath = "/" + $uploadPath
  }

  Write-Output "Creating an upload session..."
  $uploadSessionUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drives/$driveId/root:$($uploadPath):/createUploadSession"
  Write-Output "Upload Session URI: $uploadSessionUri"
  $uploadSession = Invoke-RestMethod -Method POST -headers $header -Uri $uploadSessionUri

  Write-Output "Getting local file..."
  $fileInBytes = [System.IO.File]::ReadAllBytes($PathFileToUpload)
  $fileLength = $fileInBytes.Length

  $partSizeBytes = 320 * 1024 * 4  #Uploads 1.31MiB at a time.
  $index = 0
  $start = 0
  $end = 0

  $maxloops = [Math]::Round([Math]::Ceiling($fileLength / $partSizeBytes))

  while ($fileLength -gt ($end + 1)) {
      $start = $index * $partSizeBytes
      if (($start + $partSizeBytes - 1 ) -lt $fileLength) {
          $end = ($start + $partSizeBytes - 1)
      } else {
          $end = ($start + ($fileLength - ($index * $partSizeBytes)) - 1)
      }
      [byte[]]$body = $fileInBytes[$start..$end]
      $headers = @{    
          'Content-Range' = "bytes $start-$end/$fileLength"
      }
      Write-Output "bytes $start-$end/$fileLength | Index: $index and ChunkSize: $partSizeBytes"
      Invoke-RestMethod -Method Put -Uri $uploadSession.uploadUrl -Body $body -Headers $headers | Out-Null
      $index++
      Write-Output "Percentage Complete: $([Math]::Ceiling($index/$maxloops*100)) %"
  }
}


# Authenticate to Microsoft Graph
Write-Output "Authenticating to Microsoft Graph via REST method"
$graphToken = Get-GraphAccessToken -TenantId $tenantID -ApplicationId $applicationID -ClientKey $clientKey

$dateString = Get-Date -f $dateFormat

# Upload files to SharePoint
foreach ($file in $uploadFiles) {
  $destinationFileName = ($file.destinationFileName).Replace("%%DATE%%", $dateString)
  $pathFileToUpload = $file.fileToUpload

  Write-Output "Calling function to upload file $($file.fileToUpload)"
  try {
    Upload-SharepointFile -AccessToken $graphToken -SiteServerRelativeUrl $siteServerRelativeUrl -TenantName $tenantName -LibraryName $libraryName -SharePointRelativeFolderPath $sharePointRelativeFolderPath -AlternativeFileName $destinationFileName -PathFileToUpload $pathFileToUpload
  }
  catch {
    Write-Warning "Cannot upload file $($file.fileToUpload)"
  }
}

