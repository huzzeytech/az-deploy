Configuration ClientConfig
{
    # Get Domain Admin Credential from Azure Automation Credential Storage
    param(
        [String]
        $credname
    )
    $domainCredential = Get-AutomationPSCredential $credname

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
   
    Node localhost
    {
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
            TestScript = { Test-Path 'HKLM:\SOFTWARE\Microsoft\Cryptography\Calais\SmartCards\YubiKey Smart Card' }
            Credential = $domainCredential
        }
        Script DisableNLA
        {
            GetScript = {@{}}
            SetScript = {
                (Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices -ComputerName "localhost" -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(0)
            }
            TestScript = {
                if ((Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices -ComputerName "localhost" -Filter "TerminalName='RDP-tcp'").UserAuthenticationRequired -eq "1")
                {
                    return $false
                }
                else {
                    return $true
                }
            }
            DependsOn = '[Script]InstallYKMD'
        }
    }
}