param (
    [string]$CustomDomain,
    [string]$adminUsername,
    [string]$adminPassword
)
Start-Transcript -NoClobber

$CustomDomain = "$CustomDomain-yubi.fun"
$SmartCardTemplateName = "YubiKey"
$computer = "ca1"

$password =  ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$CustomDomain\$AdminUsername", $password)
