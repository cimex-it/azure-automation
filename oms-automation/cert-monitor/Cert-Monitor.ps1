# Set variables
$WorkspaceId = Get-AutomationVariable -Name 'PingMonitorWorkspaceId'
$WorkspaceKey = Get-AutomationVariable -Name 'PingMonitorWorkspaceKey'
$LogType = 'CertMonitor'
$VariableName = 'CertMonitorWebsites'
$WebsitePort=443

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

try{
    $websitesJson = Get-AutomationVariable -Name $VariableName
} catch {
    Write-Output "Please create an Automation Variable named '$VariableName' before continuing"
    throw "Missing Automation Variable '$VariableName'"
}

$websitesJson = Get-AutomationVariable -Name $VariableName
$websites = ConvertFrom-Json $websitesJson

foreach ($website in $websites) {

    $WebsiteURL = $website.URL
    $CommonName=$WebsiteURL
    Try{
        $Conn = New-Object System.Net.Sockets.TcpClient($WebsiteURL,$WebsitePort) 
        Try {
            $Stream = New-Object System.Net.Security.SslStream($Conn.GetStream(),$false, {
                param($sender, $certificate, $chain, $sslPolicyErrors) 
                return $true
            })
            $Stream.AuthenticateAsClient($CommonName,$null,[System.Security.Authentication.SslProtocols]::Tls12, $null)

            $Cert = $Stream.Get_RemoteCertificate()
            $CN=(($cert.Subject -split "=")[1] -split ",")[0]
            $ValidTo = [datetime]::Parse($Cert.GetExpirationDatestring())

            $ValidDays = $($ValidTo - [datetime]::Now).Days

            $Properties = @{}
            $Properties.WebsiteURL = $CommonName
            $Properties.CN = $CN
            $Properties.ValidTo = $ValidTo
            $Properties.ValidDays = $ValidDays

            $Properties

            $Data = $Properties | ConvertTo-Json
            
            $EventProperties = [pscustomobject]@{Data=$Data}
            $EVENTDATA = [pscustomobject]@{EventProperties=$EventProperties}
    
            $json = "[$($EVENTDATA.EventProperties.Data)]"
            $body = ([System.Text.Encoding]::UTF8.GetBytes($json))
            
            $post = Post-LogData -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $logType
    
            if($post -eq 202 -or $post -eq 200){
                Write-output "Event written to $WorkspaceId"
            }
            else{
                Write-output "StatusCode: $post - failed to write to $WorkspaceId"
                Throw "StatusCode: $post - failed to write to $WorkspaceId"
            }
        }
        Catch { Throw $_ }
        Finally { $Conn.close() }
    }
    Catch {
    }

}
