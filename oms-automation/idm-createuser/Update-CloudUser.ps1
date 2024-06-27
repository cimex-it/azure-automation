param( 
    [Parameter(Mandatory=$true)]
    [string] $Email,
    [string] $License,
    [string] $PredUserEmail
)

try {
  #Get the token using a managed identity and connect to graph using that token
  Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
  $AccessToken = Get-AzAccessToken -ResourceTypeName MSGraph -ErrorAction Stop | select -ExpandProperty Token
  $AccessTokenSec = ConvertTo-SecureString -String $AccessToken -AsPlainText -Force
  Connect-MgGraph -AccessToken $AccessTokenSec -ErrorAction Stop | Out-Null
} catch {
  Write-Output $_.Exception.Message -ErrorAction Stop
}

Connect-ExchangeOnline -ManagedIdentity -Organization cimex.onmicrosoft.com

try {
  $user = Get-MgUser -UserId $Email
} catch {
  Write-Output $_.Exception.Message -ErrorAction Stop
}

Write-Output $user

# Add Office 365 license
$licenseGroup = Switch -Wildcard ($License) {
    "Kiosk Online*"  {"License - O365 K1"}
    "M365 Business Standard*" {"License - M365 Premium"}
}

If ($licenseGroup) {
    $group = Get-MgGroup -Filter "DisplayName eq '$licenseGroup'"
    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
}

if ($PredUserEmail -ne $null) {
  $groupMembership = Get-MgUserMemberOfAsGroup -UserId $PredUserEmail | where {$_.OnpremisesSyncEnabled -ne $true -and $_.GroupTypes -notcontains "DynamicMembership" -and $_.DisplayName -notlike "License*" -and $_.Id -ne "1b539b43-c67f-4521-8316-f1da5de67cb8"}

  Write-Output $groupMembership
  
  foreach ($group in $groupMembership) {
    if ($group.MailEnabled -eq "True" -and $group.GroupTypes -notcontains "Unified") {
        Write-Output "Adding $Email to $($group.DisplayName) (mail-enabled)."
        Add-DistributionGroupMember -Identity $group.Id -Member $user.Id -BypassSecurityGroupManagerCheck
    } else {
        Write-Output "Adding $Email to $($group.DisplayName)."
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
    }
  }
}


