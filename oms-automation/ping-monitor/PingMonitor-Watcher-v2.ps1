function Ping-Monitor 
{
    [CmdletBinding(ConfirmImpact='Low')]
    Param(
        [int]$Interval = 30,
        [string]$VariableName = 'PingMonitorDevices',
        [Switch]$RawOutput = $false
        [int]$Timeout = 1500
    )

    try{
        $networkDevicesJson = Get-AutomationVariable -Name $VariableName -ErrorAction Stop
    } catch {
        Write-Output "Please create an Automation Variable named '$VariableName' before continuing"
        throw "Missing Automation Variable '$VariableName'"
    }

    $networkDevicesJson = Get-AutomationVariable -Name $VariableName
    $networkDevices = ConvertFrom-Json $networkDevicesJson

    $IpTotal = $networkDevices.Count

    Get-Event -SourceIdentifier "ID-Ping*" | Remove-Event
    Get-EventSubscriber -SourceIdentifier "ID-Ping*" | Unregister-Event

    $networkDevices | ForEach-Object {

        [string]$VarName = "Ping_" + $_.IPAddress

        New-Variable -Name $VarName -Value (New-Object System.Net.NetworkInformation.Ping)

        Register-ObjectEvent -InputObject (Get-Variable $VarName -ValueOnly) -EventName PingCompleted -SourceIdentifier "ID-$VarName"

        (Get-Variable $VarName -ValueOnly).SendAsync($_.IPAddress,$timeout,$VarName)

        Remove-Variable $VarName

        Start-Sleep -Milliseconds $Interval
    }

    $Reply = @()

    if ($RawOutput)
    {
        Get-Event -SourceIdentifier "ID-Ping*" | foreach { 
            if ($_.SourceEventArgs.Reply.Status -eq "Success")
            {
                $Reply += $_.SourceEventArgs.Reply
            }
            Unregister-Event $_.SourceIdentifier
            Remove-Event $_.SourceIdentifier
        }
    }
    else
    {
        Get-Event -SourceIdentifier "ID-Ping*" | ForEach-Object { 
            if ($_.SourceEventArgs.Reply.Status -eq "Success")
            {
                $pinger = @{
                    IPAddress = $_.SourceEventArgs.Reply.Address.IPAddressToString
                    ResponseTime = $_.SourceEventArgs.Reply.RoundtripTime
                }
                $Reply += New-Object PSObject -Property $pinger
            }
            Unregister-Event $_.SourceIdentifier
            Remove-Event $_.SourceIdentifier
        }
    }

    if ($Reply.Count -eq 0)
    {
        Write-Verbose "Ping-IPRange : No IP address responded" -Verbose
    }

    return $Reply
}

$result = Ping-Monitor -Interval 10
$resultJson = $result | ConvertTo-Json

Invoke-AutomationWatcherAction -Data $resultJson
