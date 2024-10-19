$ErrorActionPreference = "Stop"

try
{
    # Import the Active Directory module
    Import-Module ActiveDirectory

    [string]$domainWorkgroup = "test.corp"
    [string]$domainName = "test.corp"
    [string]$userName = "Test"
    [string]$userPassword = "Passw0rd!"

    # Convert the password to a secure string
    $securePassword = ConvertTo-SecureString -String $userPassword -AsPlainText -Force

    # Create the new user
    New-ADUser -Name $userName `
            -SamAccountName $userName `
            -UserPrincipalName "$userName@$domainName" `
            -AccountPassword $securePassword `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -ChangePasswordAtLogon $false

    Write-Host "User $userName has been created successfully in the domain $domainName"
}
catch
{
    Write-Error "An error occurred: $_"
    Exit 1
}

