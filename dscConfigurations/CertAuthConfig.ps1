Configuration CertAuthConfig
{
 
    #$domainCredential = Get-AzAutomationCredential -ResourceGroupName "infra" -AutomationAccountName "yubi-test" -Name "domainCredential"
    $domainCredential = Get-AutomationPSCredential -Name "domainCredential"

    Import-DscResource -ModuleName ActiveDirectoryCSDsc
    Import-DscResource -ModuleName PSDesiredStateConfiguration
 
     Node $AllNodes.NodeName
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
     }
  }