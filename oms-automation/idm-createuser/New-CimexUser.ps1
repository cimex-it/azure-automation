param( 
    [Parameter(Mandatory=$true)]
    [string] $FullName,
    [Parameter(Mandatory=$true)]
    [string] $Email,
    [Parameter(Mandatory=$true)]
    [string] $InitialPwd,
    [string] $Position,
    [string] $Department,
    [string] $Company,
    [string] $CostCenter,
    [string] $ManagerEmail,
    [string] $License,
    [string] $PredUserEmail,
    [string] $ADOU = "OU=Users_Office_365,DC=CimexGroup,DC=cz"
)

Import-Module ActiveDirectory                        

$email = $Email.ToLower()
$login = $email.Split("@")[0]
$firstName = $FullName.Split(" ")[0]
$lastName = $FullName.Split(" ")[1]
$InitialPwdSec = ConvertTo-SecureString -String $InitialPwd -AsPlainText -Force
$costCenterShort = $CostCenter.Split("$")[1]

If ($login.Length -gt 20) { Write-Error "Login name too long."
Exit }

If (Get-ADUser -Filter "samaccountname -eq '$login'") { Write-Error "User account with this login already exists."
Exit }
  
$userPath = $ADOU
  
If (!([adsi]::Exists("LDAP://$userPath"))) { Write-Error "AD path doesn't exist."
Exit }
  
$userAccount = New-ADUser -UserPrincipalName $email -samAccountName $login -Name "$lastName $firstName" -GivenName $firstName -SurName $lastName -DisplayName "$lastName $firstName" -AccountPassword $InitialPwdSec -Path $userPath -Enabled $true -PassThru

Start-Sleep -s 10
  
# Set up email
$userAccount | Set-ADUser -EmailAddress $email -Country "CZ"

If ($position) { $userAccount | Set-ADUser -Title $position }
If ($company) { $userAccount | Set-ADUser -Company $company }
If ($department) { $userAccount | Set-ADUser -Department $department }
If ($ManagerEmail) { 
    $managerAccount = Get-ADUser -Filter "EmailAddress -eq '$managerEmail'"
    $userAccount | Set-ADUser -Manager $managerAccount }
If ($ticketNum) { $userAccount | Set-ADUser -Replace @{info="$ticketNum"} }


$userAccount | Set-ADUser -Add @{
    mailNickName=$login;
    costCenter=$costCenterShort
}

$userAccount | Set-ADUser -Add @{proxyAddresses="sip:$email,SMTP:$email" -Split ","}

# Add Office 365 license
#$licenseGroup = Switch -Wildcard ($License) {
#    "Kiosk Online*"  {"License - O365 K1"}
#    "M365 Business Standard*" {"License - M365 Standard"}
#}

#If ($licenseGroup) {
#    $group = Get-ADGroup -Filter "name -like '$licenseGroup'"
#    Add-ADGroupMember -Identity $group -Members $userAccount
#}

##

# Copy user groups

If ($predUserEmail) {
    $predUser = Get-ADUser -Filter "EmailAddress -eq '$predUserEmail'" -Properties MemberOf
    $predUser | Select-Object -ExpandProperty memberof |  Add-ADGroupMember -Members $userAccount
}

####

$statusCode = "Success"
$statusDetails = "User has been successfully created."

$objOut = [PSCustomObject]@{
    statusCode = $statusCode
    statusDetails = $statusDetails
}

$jsonOut = $objOut | ConvertTo-Json
Write-Output $jsonOut
