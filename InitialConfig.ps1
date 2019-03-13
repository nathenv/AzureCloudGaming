configuration CloudGamingClient
{
    param
    (
        [Parameter(Mandatory)]
        [pscredential]
        $Credential,

        [int]
        $PortNumber = 4711
    )

    Import-DscResource -ModuleName PackageManagement -ModuleVersion 1.3.1
    Import-DscResource -ModuleName PSDSCResources -ModuleVersion 2.10.0.0
    Import-DscResource -ModuleName StorageDsc -ModuleVersion 4.5.0.0
    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 8.5.0.0
    Import-DscResource -ModuleName NetworkingDsc -ModuleVersion 7.0.0.0

    LocalConfigurationManager 
    {
        RebootNodeIfNeeded = $true
        ActionAfterReboot  = 'ContinueConfiguration'
    }

    # Set RDP port
    Registry RdpPort
    {
        Key       = 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        ValueName = 'PortNumber'
        ValueData = $PortNumber
        Force     = $true
        Ensure    = 'Present'
    }

    Registry RdpEnabled
    {
        Key       = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
        ValueName = 'fDenyTSConnections'
        ValueData = 0
        ValueType = 'DWord'
        Force     = $true
        Ensure    = 'Present'
    }

    #region Disklayout
    <#Disk tempDisk # Until StorageDsc can reliably work with MBR disks as well
    {
        DiskId      = 1
        DiskIdType  = 'Number'
        DriveLetter = 'X'
    }#>
    Disk dataDisk
    {
        DiskId      = 2
        DriveLetter = 'L'
        #DependsOn   = '[Disk]tempDisk'
        DiskIdType  = 'Number'
        FSFormat    = 'NTFS'
        FSLabel     = 'LibraryData'
    }
    #endregion

    #region Package install
    PackageManagementSource Chocolatey
    {
        Ensure             = 'Present'
        Name               = 'Chocolatey'
        ProviderName       = 'Chocolatey'
        SourceLocation     = 'http://chocolatey.org/api/v2/'  
        InstallationPolicy = 'Trusted'
    }

    PackageManagementSource PSGallery
    {
        Ensure             = 'Present'
        Name               = 'PSGallery'
        ProviderName       = 'PowerShellGet'
        SourceLocation     = 'https://www.powershellgallery.com/api/v2'  
        InstallationPolicy = 'Trusted'
    }

    foreach ($package in @('goggalaxy', 'steam', 'origin', 'uplay'))
    {
        PackageManagement $package
        {
            Name         = $package
            ProviderName = 'Chocolatey'
            DependsOn    = '[PackageManagementSource]Chocolatey'
        }
    }

    <# Extra handling for parsec, which is currently beta    
    PackageManagement parsec
    {
        Name                 = 'parsec'
        ProviderName         = 'Chocolatey'
        DependsOn            = '[PackageManagementSource]Chocolatey'
        RequiredVersion      = "1.0.0.20180613-beta"
    }#>

    #endregion

    #region Auto-logon
    Registry AutoAdminLogon
    {
        Key       = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        ValueName = 'AutoAdminLogon'
        ValueData = 1
        ValueType = 'DWord'
        Ensure    = 'Present'
        Force     = $true
    }
    Registry AutoAdminCount
    {
        Key       = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        ValueName = 'AutoLogonCount'
        ValueData = 9999
        ValueType = 'DWord'
        Ensure    = 'Present'
        Force     = $true
    }
    Registry DefaultUserName
    {
        Key       = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        ValueName = 'DefaultUserName'
        ValueData = $Credential.UserName
        ValueType = 'String'
        Ensure    = 'Present'
        Force     = $true
    }
    Registry DefaultPassword # This is not secure in any way! Auto-logon needs to be configured for Parsec to work
    {
        Key       = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        ValueName = 'DefaultPassword'
        ValueData = $Credential.GetNetworkCredential().Password
        ValueType = 'String'
        Ensure    = 'Present'
        Force     = $true
    }
    Registry LockScreen
    {
        Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
        ValueName = 'NoLockScreen'
        ValueData = 1
        ValueType = 'DWord'
        Ensure    = 'Present'
        Force     = $true
    }
    #endregion

    #region virtual audio cable setup - not on Chocolatey :-(
    xRemoteFile VACDownload
    {
        DestinationPath = 'C:\DscDownloads\VAC460.zip'
        Uri             = 'https://software.muzychenko.net/trials/vac460.zip'
    }

    Archive VACExtract
    {
        DependsOn   = '[xRemoteFile]VACDownload'
        Path        = 'C:\DscDownloads\VAC460.zip'
        Destination = 'C:\DscDownloads\VACSetup'
        Force       = $true
    }

    xPackage VACInstall
    {
        Path      = 'C:\DscDownloads\VACSetup\setup64.exe'
        Arguments = '-s -k 30570681-0a8b-46e5-8cb2-d835f43af0c5'
        Name      = 'Virtual Audio Cable'
        ProductId = '83ed7f0e-2028-4956-b0b4-39c76fdaef1d'
        Ensure    = 'Present'
    }
    
    Service audio
    {
        Name        = 'audiosrv'
        StartupType = 'Automatic'
        State       = 'Running'
    }

    Service TermServ
    {
        Name        = 'termservice'
        StartupType = 'Automatic'
        State       = 'Running'
    }
    #endregion

    #region Display driver
    Script TeslaConfig
    {
        GetScript  = {@{Result = & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" | Foreach-Object { if ($_ -match "(?<Guid>\d{8}:\d{2}:\d{2}\.\d)") {$Matches.Guid}}}}
        TestScript = {[bool](& "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" | Foreach-Object { if ($_ -match "\s*WDDM\s*") {$Matches.0}})}
        SetScript  = {
            $guid = & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" | Foreach-Object { if ($_ -match "(?<Guid>\d{8}:\d{2}:\d{2}\.\d)") {$Matches.Guid}}
            [void] (& "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" -g $guid -dm 0)
            $global:DSCMachineStatus = 1
        }
    }
    #endregion
    
    #region Firewall
    Firewall rdp_udp
    {
        Name                = 'RemoteDesktop-UserMode-In-UDP_Custom'
        LocalPort           = $PortNumber
        Action              = 'Allow'
        Protocol            = 'UDP'
        Profile             = 'Domain', 'Private', 'Public'
        Description         = "Inbound rule for the Remote Desktop service to allow RDP traffic. [UDP $PortNumber]"
        DisplayName         = 'Remote Desktop - User Mode (UDP-In) Custom'
        Direction           = 'Inbound'
        Enabled             = 'True'
        Ensure = 'Present'
    }

    Firewall rdp_tcp
    {
        Name                = 'RemoteDesktop-UserMode-In-TCP_Custom'
        LocalPort           = $PortNumber
        Action              = 'Allow'
        Protocol            = 'TCP'
        Profile             = 'Domain', 'Private', 'Public'
        Description         = "Inbound rule for the Remote Desktop service to allow RDP traffic. [TCP $PortNumber]"
        DisplayName         = 'Remote Desktop - User Mode (TCP-In) Custom'
        Direction           = 'Inbound'
        Enabled             = 'True'
        Ensure = 'Present'
    }

    Firewall ParsecIn
    {
        Name      = 'Parsec-inbound-UDP'
        LocalPort = @(21277..21279)
        DisplayName = 'Parsec inbound traffic'
        Action    = 'Allow'
        Protocol  = 'UDP'
        Profile   = 'Domain', 'Private', 'Public'
        Enabled   = 'True'
        Ensure = 'Present'
    }
    #endregion
}
