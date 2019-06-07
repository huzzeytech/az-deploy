Configuration CertAuthConfig
{
    # Parameter help description
    param(
        [String]
        $credname
    )

    $domainCredential = Get-AutomationPSCredential $credname

    Import-DscResource -ModuleName ActiveDirectoryCSDsc
    Import-DscResource -ModuleName PSDesiredStateConfiguration
 
     Node localhost
     {

        # Install the ADCS Certificate Authority
        WindowsFeature ADCSCA {
            Name = 'ADCS-Cert-Authority'
            Ensure = 'Present'
        }
        
        # Configure the CA as Standalone Root CA
        AdcsCertificationAuthority CertificateAuthority
        {
            Ensure = 'Present'
            Credential = $domainCredential
            IsSingleInstance = "Yes"
            CAType = 'EnterpriseRootCA'
            ValidityPeriod = 'Years'
            ValidityPeriodUnits = 20
            CryptoProviderName = 'RSA#Microsoft Software Key Storage Provider'
            HashAlgorithmName = 'SHA256'
            KeyLength = 4096
            DependsOn = '[WindowsFeature]ADCSCA' 
        }
        WindowsFeature RSAT-ADCS 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-ADCS' 
            DependsOn = '[WindowsFeature]ADCSCA' 
        }
        WindowsFeature RSAT-ADCS-Mgmt 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-ADCS-Mgmt' 
            DependsOn = '[WindowsFeature]ADCSCA' 
        }
        # Pre-Req for Adding Certificate Template
        WindowsFeature RSAT-AD-PowerShell 
        { 
            Ensure = 'Present' 
            Name = 'RSAT-AD-PowerShell' 
        }
        Script ApplyTemplate
        {
            GetScript = {@{}}
            SetScript = {
                Function Get-RandomHex {
                    param ([int]$Length)
                        $Hex = '0123456789ABCDEF'
                        [string]$Return = $null
                        For ($i=1;$i -le $length;$i++) {
                            $Return += $Hex.Substring((Get-Random -Minimum 0 -Maximum 16),1)
                        }
                        Return $Return
                    }
                    
                    Function IsUniqueOID {
                    param ($cn,$TemplateOID,$Server,$ConfigNC)
                        $Search = Get-ADObject -Server $Server `
                            -SearchBase "CN=OID,CN=Public Key Services,CN=Services,$ConfigNC" `
                            -Filter {cn -eq $cn -and msPKI-Cert-Template-OID -eq $TemplateOID}
                        If ($Search) {$False} Else {$True}
                    }
                    
                    Function New-TemplateOID {
                    Param($Server,$ConfigNC)
                        <#
                        OID CN/Name                    [10000000-99999999].[32 hex characters]
                        OID msPKI-Cert-Template-OID    [Forest base OID].[1000000-99999999].[10000000-99999999]  <--- second number same as first number in OID name
                        #>
                        do {
                            $OID_Part_1 = Get-Random -Minimum 1000000  -Maximum 99999999
                            $OID_Part_2 = Get-Random -Minimum 10000000 -Maximum 99999999
                            $OID_Part_3 = Get-RandomHex -Length 32
                            $OID_Forest = Get-ADObject -Server $Server `
                                -Identity "CN=OID,CN=Public Key Services,CN=Services,$ConfigNC" `
                                -Properties msPKI-Cert-Template-OID |
                                Select-Object -ExpandProperty msPKI-Cert-Template-OID
                            $msPKICertTemplateOID = "$OID_Forest.$OID_Part_1.$OID_Part_2"
                            $Name = "$OID_Part_2.$OID_Part_3"
                        } until (IsUniqueOID -cn $Name -TemplateOID $msPKICertTemplateOID -Server $Server -ConfigNC $ConfigNC)
                        Return @{
                            TemplateOID  = $msPKICertTemplateOID
                            TemplateName = $Name
                        }
                    }
                    
                    
                    <#
                    .SYNOPSIS
                    Creates a new Active Directory Certificate Services template for PowerShell CMS encryption.
                    .DESCRIPTION
                    The template can be used for CMS cmdlet encryption and/or DSC credential encryption.
                    .NOTES
                    The OID generated does not use the approved API, but it works well. Please report any issues.
                    .PARAMETER DisplayName
                    DisplayName for the certificate template.
                    .PARAMETER Server
                    Active Directory Domain Controller to target for the operation.
                    .PARAMETER GroupName
                    Global group(s) to assign permissions to enroll the template.
                    Specify in DOMAIN\GROUP naming convention.
                    Default is Domain Computers.
                    .PARAMETER AutoEnroll
                    Switch to also grant AutoEnroll to the group(s).
                    .PARAMETER Publish
                    Publish the template to all Certificate Authority issuers.
                    Default is only Enroll.
                    .EXAMPLE
                    New-ADCSTemplateForPSEncryption -DisplayName PowerShellCMS
                    .EXAMPLE
                    New-ADCSTemplateForPSEncryption -DisplayName PowerShellCMS -Server dc1.contoso.com -GroupName G_DSCNodes -AutoEnroll -Publish
                    .EXAMPLE
                    # From a client configured for AD CS autoenrollment:
                    $Req = @{
                        Template          = 'PSEncryption'
                        Url               = 'ldap:'
                        CertStoreLocation = 'Cert:\LocalMachine\My'
                    }
                    Get-Certificate @Req
                    # Note: If you have the Carbon module installed, it conflicts with Get-Certificate native cmdlet.
                    
                    $DocEncrCert = (dir Cert:\LocalMachine\My -DocumentEncryptionCert | Sort-Object NotBefore)[-1]
                    Protect-CmsMessage -To $DocEncrCert -Content "Encrypted with my new cert from the new template!"
                    #>
                    
                    function Get-YKSCTemplate {
                    param(
                        [parameter(Mandatory)]
                        [string]$DisplayName
                    )
                        $Server = (Get-ADDomainController -Discover -ForceDiscover -Writable).HostName[0]
                        $ConfigNC = $((Get-ADRootDSE -Server $Server).configurationNamingContext)
                        $TemplateName = "CN=$DisplayName,CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigNC"
                        try {
                            get-adobject -server $Server -Identity $TemplateName
                            write-host "Template exist"
                        }
                        catch{
                            write-host "Template does not exist"
                        }
                        
                    }
                    
                    Function New-YKSCTemplate {
                    param(
                        [parameter(Mandatory)]
                        [string]$DisplayName,
                        [string]$Server = 'dc1',
                        #[string[]]$GroupName = "$((Get-ADDomain).NetBIOSName)\Authenticated Users",
                        [string[]]$GroupName = "Authenticated Users",
                        [switch]$EOB,
                        [switch]$AutoEnroll,
                        [switch]$Publish
                    )
                        Import-Module ActiveDirectory
                        $ConfigNC = $((Get-ADRootDSE -Server $Server).configurationNamingContext)
                    
                        #region CREATE OID
                        <#
                        CN                              : 14891906.F2AC4390685318BD1D950A66EDB50FF4
                        DisplayName                     : TemplateNameHere
                        DistinguishedName               : CN=14891906.F2AC4390685318BD1D950A66EDB50FF4,CN=OID,CN=Public Key Services,CN=Services,CN=Configuration,DC=contoso,DC=com
                        dSCorePropagationData           : {1/1/1601 12:00:00 AM}
                        flags                           : 1
                        instanceType                    : 4
                        msPKI-Cert-Template-OID         : 1.3.6.1.4.1.311.21.8.11489019.14294623.5588661.594850.12204198.151.6616009.14891906
                        Name                            : 14891906.F2AC4390685318BD1D950A66EDB50FF4
                        ObjectCategory                  : CN=ms-PKI-Enterprise-Oid,CN=Schema,CN=Configuration,DC=contoso,DC=com
                        ObjectClass                     : msPKI-Enterprise-Oid
                        #>
                        $OID = New-TemplateOID -Server $Server -ConfigNC $ConfigNC
                        $TemplateOIDPath = "CN=OID,CN=Public Key Services,CN=Services,$ConfigNC"
                        $oa = @{
                            'DisplayName' = $DisplayName
                            'flags' = [System.Int32]'1'
                            'msPKI-Cert-Template-OID' = $OID.TemplateOID
                        }
                        New-ADObject -Path $TemplateOIDPath -OtherAttributes $oa -Name $OID.TemplateName -Type 'msPKI-Enterprise-Oid' -Server $Server
                        #endregion
                    
                        #region CREATE TEMPLATE
                        # https://docs.microsoft.com/en-us/powershell/dsc/securemof#certificate-requirements
                        # https://blogs.technet.microsoft.com/option_explicit/2012/04/09/pki-certificates-and-the-x-509-standard/
                        # https://technet.microsoft.com/en-us/library/cc776447(v=ws.10).aspx
                        $oa_base = @{
                            'flags' = [System.Int32]'131584'
                            'msPKI-Certificate-Application-Policy' = [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]@('1.3.6.1.4.1.311.20.2.2','1.3.6.1.5.5.7.3.2')
                            'msPKI-Certificate-Name-Flag' = [System.Int32]'-2113929216'
                            'msPKI-Enrollment-Flag' = [System.Int32]'8489'
                            'msPKI-Minimal-Key-Size' = [System.Int32]'2048'
                            'msPKI-Private-Key-Flag' = [System.Int32]'101056640'
                            'msPKI-Template-Minor-Revision' = [System.Int32]'4'
                            'msPKI-Template-Schema-Version' = [System.Int32]'4'
                            'pKIMaxIssuingDepth' = [System.Int32]'0'
                            'ObjectClass' = [System.String]'pKICertificateTemplate'
                            'pKICriticalExtensions' = [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]@('2.5.29.15')
                            'pKIDefaultCSPs' = [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]@('1,Microsoft Smart Card Key Storage Provider')
                            'pKIDefaultKeySpec' = [System.Int32]'1'
                            'pKIExpirationPeriod' = [System.Byte[]]@('0','64','57','135','46','225','254','255')
                            'pKIExtendedKeyUsage' = [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]@('1.3.6.1.4.1.311.20.2.2','1.3.6.1.5.5.7.3.2')
                            'pKIKeyUsage' = [System.Byte[]]@('160', '0')
                            'pKIOverlapPeriod' = [System.Byte[]]@('0','128','166','10','255','222','255','255')
                            'revision' = [System.Int32]'100'
                            'msPKI-Cert-Template-OID' = $OID.TemplateOID
                        }
                    
                        If ($EOB) {
                            $oa_ext = @{
                                        'msPKI-RA-Signature' = [System.Int32]'1'
                                        'msPKI-RA-Application-Policies' = [System.String]'msPKI-RA-Application-Policies`PZPWSTR`1.3.6.1.4.1.311.20.2.1`msPKI-Asymmetric-Algorithm`PZPWSTR`RSA`msPKI-Hash-Algorithm`PZPWSTR`SHA256`msPKI-Key-Usage`DWORD`16777215`msPKI-Symmetric-Algorithm`PZPWSTR`3DES`msPKI-Symmetric-Key-Length`DWORD`168'
                                        }    
                        } Else {
                            $oa_ext = @{
                                        'msPKI-RA-Signature' = [System.Int32]'0'
                                        'msPKI-RA-Application-Policies' = [System.String]'msPKI-Asymmetric-Algorithm`PZPWSTR`RSA`msPKI-Hash-Algorithm`PZPWSTR`SHA256`msPKI-Key-Usage`DWORD`16777215`msPKI-Symmetric-Algorithm`PZPWSTR`3DES`msPKI-Symmetric-Key-Length`DWORD`168'
                                        }
                        }
                    
                        $oa = $oa_base + $oa_ext
                    
                    
                        $TemplatePath = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigNC"
                        New-ADObject -Path $TemplatePath -OtherAttributes $oa -Name $DisplayName -DisplayName $DisplayName -Type pKICertificateTemplate -Server $Server
                        #endregion
                    
                        #region PERMISSIONS
                        ## Potential issue here that the AD: drive may not be targetting the selected DC in the -SERVER parameter
                        $TemplatePath            = "AD:\CN=$DisplayName,CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigNC"
                        $acl                     = Get-ACL $TemplatePath
                        $InheritedObjectType = [GUID]'00000000-0000-0000-0000-000000000000'
                        ForEach ($Group in $GroupName) {
                            $ObjectType          = [GUID]'0e10c968-78fb-11d2-90d4-00c04f79dc55'
                            $account             = New-Object System.Security.Principal.NTAccount($Group)
                            $sid                 = $account.Translate([System.Security.Principal.SecurityIdentifier])
                            $ace                 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
                                $sid, 'ExtendedRight, ReadProperty, GenericExecute', 'Allow', $ObjectType, 'None', $InheritedObjectType
                            $acl.AddAccessRule($ace)
                    
                            If ($AutoEnroll) {
                                $ObjectType      = [GUID]'a05b8cc2-17bc-4802-a710-e7c15ab866a2'
                                $ace             = New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
                                    $sid, 'ExtendedRight, ReadProperty, GenericExecute', 'Allow', $ObjectType, 'None', $InheritedObjectType
                                $acl.AddAccessRule($ace)
                            }
                        }
                        Set-ACL $TemplatePath -AclObject $acl
                        #endregion
                    
                        #region ISSUE
                        If ($Publish) {
                            ### WARNING: Issues on all available CAs. Test in your environment.
                            $EnrollmentPath = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$ConfigNC"
                            $CAs = Get-ADObject -SearchBase $EnrollmentPath -SearchScope OneLevel -Filter * -Server $Server
                            ForEach ($CA in $CAs) {
                                Set-ADObject -Identity $CA.DistinguishedName -Add @{certificateTemplates=$DisplayName} -Server $Server
                            }
                        }
                        #endregion
                    }
                    
                    Export-ModuleMember -Function New-YKSCTemplate,Get-YKSCTemplate
                    New-YKSCTemplate -DisplayName "YubiKey" -AutoEnroll -Publish
            }
            TestScript = {
                
                if(certutil -templatecas "YubiKey" | select-string  -simplematch "command completed successfully" -quiet)
                {
                    write-verbose "The certificate template is already present on this machine."
                    return $true 
                }
                else {
                    Write-Verbose "Need to fix certificate template."
                    return $false
                }
            }
            Credential = $domainCredential
            DependsOn = '[WindowsFeature]RSAT-ADCS-Mgmt', '[Script]InstallYKMD', '[WindowsFeature]RSAT-AD-PowerShell'
        }
        Script InstallYKMD
        {
            GetScript = {@{}}
            SetScript = {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                New-Item -Path 'C:\temp' -ItemType Directory
                $url = "https://github.com/huzzeytech/az-deploy/raw/master/etc/ykmd.zip"
                $output = "C:\temp\ykmd.zip"
                (New-Object System.Net.WebClient).DownloadFile($url, $output)

                $sourcefileFullpath = "C:\temp\ykmd.zip"
                $cabfile = "YubiKey-Minidriver-4.0.4.164.cab"

                $registryPath = "HKLM:\Software\Yubico\YKMD"
                $temp = "C:\temp"
                $destination = "ykmd"
                $fullpath = $temp+"\"+$destination
                $destA = "C:\Windows\system32"
                $destB = "C:\Windows\SysWOW64"

                #extact the contents of the zip folder
                Expand-Archive -Path $sourcefileFullpath -DestinationPath $fullpath
                cmd.exe /c expand $fullpath\$cabfile -F:* $fullpath | Out-Null
                Get-ChildItem $fullpath -Recurse -Filter "*inf" | ForEach-Object { PNPUtil.exe /add-driver $_.FullName /install }

                #import the registry keys
                Invoke-Command {reg import $fullpath\yubikey.reg *>&1 | Out-Null}

                #initate the driver
                cmd.exe /c DrvInst.exe "2" "11" "ROOT\SMARTCARD\0000" "$fullpath\ykmd.inf" "ykmd.inf:e5735744d5c8dcef:Yubico64_61_install:4.0.4.164:scfilter\cid_597562696b657934" "46c3051cd" "000000000009B4" 

                #copy dll's to correct locations
                Copy-item $fullpath\ykmd64.dll -Destination $destA\ykmd.dll -Passthru -Force  
                Copy-Item $fullpath\ykmd.dll -Destination $destB\ykmd.dll -Passthru -Force

                #enable the Smart Card Service
                Get-Service -Name "Scardsvr" | Set-Service -StartupType Automatic
            }
            TestScript = { Test-Path "C:\temp" }
        }
        Script DownloadScript
        {
            GetScript = {@{}}
            SetScript = {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                New-Item -Path 'C:\dsc' -ItemType Directory
                $url = "https://raw.githubusercontent.com/huzzeytech/az-deploy/master/dscConfigurations/CertAuthConfig.ps1"
                $output = "C:\dsc\CertAuthConfig.ps1"
                (New-Object System.Net.WebClient).DownloadFile($url, $output)
            }
            TestScript = { Test-Path "C:\dsc" }
        }
     }
  }