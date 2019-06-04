Configuration CertAuthConfig

{

 # Parameter help description

 param

 (

 $credname

 )
 

 #Write-Verbose $domainCredential

 Import-DscResource -ModuleName ActiveDirectoryCSDsc

 Import-DscResource -ModuleName PSDesiredStateConfiguration
 

 $domainCredential = Get-AutomationPSCredential -Name $credname

 $usr = $domainCredential.GetNetworkCredential().UserName

 $pwd = $domainCredential.GetNetworkCredential().Password
 

 Node localhost

 {

 Script s

 {

 SetScript = {Write-Verbose $using:usr -Verbose

 Write-Verbose $using:pwd -Verbose}
 

 GetScript = {@{}}

 TestScript = {return $false}

 }
 

 Script runasuser

 {

 SetScript = {

 Write-Verbose (whoami) -Verbose

 }

 TestScript = {return $false}

 GetScript = {@{}}

 PsDscRunAsCredential = $domainCredential

 }
 

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

 }

}