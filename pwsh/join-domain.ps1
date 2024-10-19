$ErrorActionPreference = "Stop"
try {
    [string]$domainWorkgroup   = "test.corp"
    [string]$domainName        = "test.corp"
    [string]$userName          = "Test"
    [string]$userPassword      = "Passw0rd!"

    $userName = $domainName + "\" + $userName

    $objComputer = Get-WmiObject -Class "Win32_ComputerSystem"

    $result = $objComputer.JoinDomainOrWorkgroup($domainName, $userPassword, $userName, $Null, 3)

    if ($result.ReturnValue -eq 0) {
        Write-Host "Successfully joined the domain $domainName"
    } else {
        throw "Failed to join the domain. Return value: $($result.ReturnValue)"
    }
}
catch {
    Write-Error "An error occurred: $_"
    Exit 1
}
