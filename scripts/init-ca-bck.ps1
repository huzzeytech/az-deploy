param (
    [string]$CustomDomain,
    [string]$adminUsername,
    [string]$adminPassword
)
Start-Transcript -NoClobber

$CustomDomain = "$CustomDomain-yubi.fun"
$SmartCardTemplateName = "YubiKey"

$password =  ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$CustomDomain\$AdminUsername", $password)

Write-Verbose -Verbose "Entering Custom Script Extension..."

Invoke-Command -Credential $credential -ComputerName $env:COMPUTERNAME -ArgumentList $PSScriptRoot -ScriptBlock {
    param 
    (
      $workingDir
    )
   
    #################################
    # Elevated custom scripts go here 
    #################################
    Write-Verbose -Verbose "Entering Elevated Custom Script Commands..."
    if (!(Get-WindowsFeature | Where-Object {$_.name -eq "Adcs-Cert-Authority" -and $_.InstallState -eq "Installed"}))
    {
        Add-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools
        Install-AdcsCertificationAuthority –CAType EnterpriseRootCA –CACommonName "RootCA" –KeyLength 2048 –HashAlgorithm SHA256 –CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -force
    }
    <# if (Get-Service "Active Directory Certificate Services" | Where {$_.status –eq 'Stopped'})
    {
        Start-Service "Active Directory Certificate Services"
        Start-Sleep -Seconds 30
    } #>
}

<# $ConfigContext = ([ADSI]"LDAP://RootDSE").ConfigurationNamingContext 
$ADSI = [ADSI]"LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigContext" 

$NewTempl = $ADSI.Create("pKICertificateTemplate", "CN=$SmartCardTemplateName") 
$NewTempl.put("distinguishedName","CN=$SmartCardTemplateName,CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigContext") 

$NewTempl.put("flags","131584")
$NewTempl.put("displayName","$SmartCardTemplateName")
$NewTempl.put("revision","100")
$NewTempl.put("pKIDefaultKeySpec","1")
$NewTempl.SetInfo()

$NewTempl.put("pKIMaxIssuingDepth","0")
$NewTempl.put("pKICriticalExtensions","2.5.29.15")
$NewTempl.put("pKIExtendedKeyUsage",@("1.3.6.1.4.1.311.20.2.2","1.3.6.1.5.5.7.3.2"))
$NewTempl.put("pKIDefaultCSPs","1,Microsoft Smart Card Key Storage Provider")
$NewTempl.put("msPKI-RA-Signature","0")
$NewTempl.put("pKIExpirationPeriod","1 Years")
$NewTempl.put("pKIOverlapPeriod","6 Weeks")
$NewTempl.put("msPKI-Enrollment-Flag","8489")
$NewTempl.put("msPKI-Private-Key-Flag","101056640")
$NewTempl.put("msPKI-Certificate-Name-Flag","-2113929216")
$NewTempl.put("msPKI-Minimal-Key-Size","2048")
$NewTempl.put("msPKI-Template-Schema-Version","4")
$NewTempl.put("msPKI-Template-Minor-Revision","4")
$NewTempl.put("msPKI-Cert-Template-OID","1.3.6.1.4.1.311.21.8.9748629.12742570.15485066.2065389.6488713.215.15132743.7747992")
$NewTempl.put("msPKI-Certificate-Application-Policy",@("1.3.6.1.4.1.311.20.2.2","1.3.6.1.5.5.7.3.2"))
$NewTempl.put("msPKI-RA-Application-Policies","msPKI-Asymmetric-Algorithm``PZPWSTR``RSA``msPKI-Hash-Algorithm``PZPWSTR``SHA256``msPKI-Key-Usage``DWORD``16777215``msPKI-Symmetric-Algorithm``PZPWSTR``3DES``msPKI-Symmetric-Key-Length``DWORD``168")

$NewTempl.SetInfo()

$WATempl = $ADSI.psbase.children | where {$_.displayName -match "Smartcard Logon"}

$NewTempl.pKIExpirationPeriod = $WATempl.pKIExpirationPeriod
$NewTempl.pKIOverlapPeriod = $WATempl.pKIOverlapPeriod
$NewTempl.SetInfo()

$WATempl2 = $ADSI.psbase.children | where {$_.displayName -match "Smartcard Logon"}


$NewTempl.pKIKeyUsage = $WATempl2.pKIKeyUsage
$NewTempl.SetInfo()
$NewTempl | select *

$acl = $NewTempl.psbase.ObjectSecurity
$acl | select -ExpandProperty Access

$AdObj = New-Object System.Security.Principal.NTAccount("Authenticated Users")
$identity = $AdObj.Translate([System.Security.Principal.SecurityIdentifier])
$adRights = "ReadProperty, ExtendedRight, GenericExecute"
$type = "Allow"

$ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity,$adRights,$type)
$NewTempl.psbase.ObjectSecurity.SetAccessRule($ACE)
$NewTempl.psbase.commitchanges()

$AdObj = New-Object System.Security.Principal.NTAccount("$CustomDomain\BadAdmin")
$identity = $AdObj.Translate([System.Security.Principal.SecurityIdentifier])
$adRights = "GenericAll"
$type = "Allow"

$ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity,$adRights,$type)
$NewTempl.psbase.ObjectSecurity.SetAccessRule($ACE)
$NewTempl.psbase.commitchanges()

$AdObj = New-Object System.Security.Principal.NTAccount("$CustomDomain\Enterprise Admins")
$identity = $AdObj.Translate([System.Security.Principal.SecurityIdentifier])
$adRights = "GenericAll"
$type = "Allow"

$ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity,$adRights,$type)
$NewTempl.psbase.ObjectSecurity.SetAccessRule($ACE)
$NewTempl.psbase.commitchanges()

Add-CATemplate -Name $SmartCardTemplateName -force #> 