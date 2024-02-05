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
  Connect-Graph -AccessToken $AccessToken -ErrorAction Stop | Out-Null
} catch {
  Write-Error $_.Exception.Message -ErrorAction Stop
}

try {
  $user = Get-MgUser -UserId $Email
} catch {
  Write-Error $_.Exception.Message -ErrorAction Stop
}

if ($PredUserEmail -ne $null) {
  $groupMembership = (Get-MgUserMemberOfAsGroup -UserId $PredUserEmail | where {$_.OnpremisesSyncEnabled -ne $true}).Id

  foreach ($groupId in $groupMembership) {
    New-MgGroupMember -GroupId $groupId -DirectoryObjectId $user.Id
  }
}