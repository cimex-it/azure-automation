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
    [string] $ManagerEmail,
    [string] $ADOU = "OU=Users_Office_365,DC=CimexGroup,DC=cz"
)

Import-Module ActiveDirectory                        

$email = $Email.ToLower()
$login = $email.Split("@")[0]
$firstName = $FullName.Split(" ")[0]
$lastName = $FullName.Split(" ")[1]
$InitialPwdSec = ConvertTo-SecureString -String $InitialPwd -AsPlainText -Force

If ($login.Length -gt 20) { Write-Error "Login name too long."
Exit }

If (Get-ADUser -Filter "samaccountname -eq '$login'") { Write-Error "User account with this login already exists."
Exit }
  
$userPath = $ADOU
  
if (!([adsi]::Exists("LDAP://$userPath"))) { Write-Error "AD path doesn't exist."
Exit }
  
$userAccount = New-ADUser -UserPrincipalName $email -samAccountName $login -Name "$firstName $lastName" -GivenName $firstName -SurName $lastName -DisplayName "$firstName $lastName" -AccountPassword $InitialPwdSec -Path $userPath -Enabled $true -PassThru

Start-Sleep -s 10
  
# Set up email
$userAccount | Set-ADUser -EmailAddress $email -Country "CZ"

If ($position) { $userAccount | Set-ADUser -Title $position }
If ($company) { $userAccount | Set-ADUser -Company $company }
If ($department) { $userAccount | Set-ADUser -Department $department }
If ($ManagerEmail) { 
    $managerAccount = get-aduser -Filter "EmailAddress -eq '$managerEmail'"
    $userAccount | Set-ADUser -Manager $managerAccount }
If ($ticketNum) { $userAccount | Set-ADUser -Replace @{info="$ticketNum"} }


$userAccount | Set-ADUser -Add @{
    mailNickName=$login;
}

$userAccount | Set-ADUser -Add @{proxyAddresses="sip:$email,SMTP:$email" -Split ","}

$licenseGroup = "License - O365 E3"
$group = Get-ADGroup -Filter "name -like '$licenseGroup'"

Add-ADGroupMember -Identity $group -Members $userAccount