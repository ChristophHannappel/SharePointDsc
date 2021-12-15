[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPInstallPrereqs'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Initialize tests
                function New-SPDscMockPrereq
                {
                    param
                    (
                        [Parameter(Mandatory = $true)]
                        [String]
                        $Name,

                        [Parameter()]
                        [String[]]
                        $BundleUpgradeCode,

                        [Parameter()]
                        [String]
                        $DisplayVersion
                    )
                    $object = New-Object -TypeName System.Object
                    $object | Add-Member -Type NoteProperty `
                        -Name "DisplayName" `
                        -Value $Name

                    $object | Add-Member -Type NoteProperty `
                        -Name "BundleUpgradeCode" `
                        -Value $BundleUpgradeCode

                    $object | Add-Member -Type NoteProperty `
                        -Name "DisplayVersion" `
                        -Value $DisplayVersion

                    return $object
                }

                if ($null -eq (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue))
                {
                    function Get-WindowsFeature
                    {
                    }
                }
                if ($null -eq (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue))
                {
                    function Install-WindowsFeature
                    {
                    }
                }

                # Mocks for all contexts
                Mock -CommandName Get-ItemProperty -ParameterFilter {
                    $Path -eq "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                } -MockWith {
                    return @()
                }

                Mock -CommandName Get-ChildItem {
                    $full = @{
                        Version     = "4.5.0.0"
                        Release     = "0"
                        PSChildName = "Full"
                    }

                    $client = @{
                        Version     = "4.5.0.0"
                        Release     = "0"
                        PSChildName = "Client"
                    }

                    $returnval = @($full, $client)
                    $returnVal = $returnVal | Add-Member ScriptMethod GetValue { return 380000 } -PassThru
                    return $returnval
                }

                Mock -CommandName Get-ItemProperty -ParameterFilter {
                    $Path -eq "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                } -MockWith {
                    return @()
                }

                Mock -CommandName Test-Path -MockWith {
                    return $true
                }

                Mock -CommandName Get-SPDscOSVersion -MockWith {
                    if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 16 -and
                        $Global:SPDscHelper.CurrentStubBuildNumber.Build -gt 10000)
                    {
                        # SharePoint 2019 / SPSE
                        return @{
                            Major = 10
                            Minor = 0
                            Build = 17763
                        }
                    }
                    else
                    {
                        # SharePoint 2013 / 2016
                        return @{
                            Major = 6
                            Minor = 3
                        }
                    }
                }

                Mock -CommandName Get-WindowsFeature -MockWith {
                    return @(@{
                            Name      = "ExampleFeature"
                            Installed = $false
                        })
                }

                Mock -CommandName Get-SPDscAssemblyVersion {
                    return $Global:SPDscHelper.CurrentStubBuildNumber.Major
                }

                Mock -CommandName Get-SPDscBuildVersion {
                    return $Global:SPDscHelper.CurrentStubBuildNumber.Build
                }

                function Add-SPDscEvent
                {
                    param (
                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Message,

                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Source,

                        [Parameter()]
                        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
                        [System.String]
                        $EntryType,

                        [Parameter()]
                        [System.UInt32]
                        $EventID
                    )
                }
            }

            # Test contexts
            Context -Name "Prerequisites are not installed but should be and are to be installed in online mode" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $true
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-ItemProperty -MockWith {
                        return @()
                    } -ParameterFilter { $null -ne $Path }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the prerequisite installer from the set method and records the need for a reboot" {
                    Mock -CommandName Start-Process { return @{ ExitCode = 3010 } }

                    Set-TargetResource @testParams
                    Assert-MockCalled Start-Process
                }

                It "Should call the prerequisite installer from the set method and a pending reboot is preventing it from running" {
                    Mock -CommandName Start-Process { return @{ ExitCode = 1001 } }

                    Set-TargetResource @testParams
                    Assert-MockCalled Start-Process
                }

                It "Should call the prerequisite installer from the set method and passes a successful installation" {
                    Mock -CommandName Start-Process { return @{ ExitCode = 0 } }

                    Set-TargetResource @testParams
                    Assert-MockCalled Start-Process
                }

                It "Should call the prerequisite installer from the set method when the prerequisite installer is already running" {
                    Mock -CommandName Start-Process { return @{ ExitCode = 1 } }

                    { Set-TargetResource @testParams } | Should -Throw "already running"
                }

                It "Should call the prerequisite installer from the set method and invalid arguments are passed to the installer" {
                    Mock -CommandName Start-Process { return @{ ExitCode = 2 } }

                    { Set-TargetResource @testParams } | Should -Throw "Invalid command line parameters"
                }

                It "Should call the prerequisite installer from the set method and throws for unknown error codes" {
                    Mock -CommandName Start-Process { return @{ ExitCode = -1 } }

                    { Set-TargetResource @testParams } | Should -Throw "unknown exit code"
                }
            }

            Context -Name "Prerequisites are installed and should be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $true
                        Ensure           = "Present"
                    }

                    switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
                    {
                        15
                        {
                            Mock -CommandName Get-ItemProperty -ParameterFilter {
                                $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                            } -MockWith {
                                return @(
                                    (New-SPDscMockPrereq -Name "Microsoft CCR and DSS Runtime 2008 R3"),
                                    (New-SPDscMockPrereq -Name "Microsoft Sync Framework Runtime v1.0 SP1 (x64)"),
                                    (New-SPDscMockPrereq -Name "AppFabric 1.1 for Windows Server"),
                                    (New-SPDscMockPrereq -Name "WCF Data Services 5.6.0 Runtime"),
                                    (New-SPDscMockPrereq -Name "WCF Data Services 5.0 (for OData v3) Primary Components"),
                                    (New-SPDscMockPrereq -Name "Microsoft SQL Server 2008 R2 Native Client"),
                                    (New-SPDscMockPrereq -Name "Active Directory Rights Management Services Client 2.0"),
                                    (New-SPDscMockPrereq -Name "Microsoft Identity Extensions" )
                                )
                            }
                        }
                        16
                        {
                            if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 10000)
                            {
                                # SharePoint 2016
                                Mock -CommandName Get-ItemProperty -ParameterFilter {
                                    $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                                } -MockWith {
                                    return @(
                                        (New-SPDscMockPrereq -Name "Microsoft CCR and DSS Runtime 2008 R3"),
                                        (New-SPDscMockPrereq -Name "Microsoft Sync Framework Runtime v1.0 SP1 (x64)"),
                                        (New-SPDscMockPrereq -Name "AppFabric 1.1 for Windows Server"),
                                        (New-SPDscMockPrereq -Name "WCF Data Services 5.6.0 Runtime"),
                                        (New-SPDscMockPrereq -Name "Microsoft ODBC Driver 11 for SQL Server"),
                                        (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2012 x64 Minimum Runtime - 11.0.61030"),
                                        (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2012 x64 Additional Runtime - 11.0.61030"),
                                        (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2015 Redistributable (x64) - 14.0.23026" -BundleUpgradeCode @("{C146EF48-4D31-3C3D-A2C5-1E91AF8A0A9B}") -DisplayVersion "14.0.23026.0"),
                                        (New-SPDscMockPrereq -Name "Microsoft SQL Server 2012 Native Client"),
                                        (New-SPDscMockPrereq -Name "Active Directory Rights Management Services Client 2.1"),
                                        (New-SPDscMockPrereq -Name "Microsoft Identity Extensions")
                                    )
                                }
                            }
                            elseif ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 13000)
                            {
                                # SharePoint 2019
                                Mock -CommandName Get-ItemProperty -ParameterFilter {
                                    $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                                } -MockWith {
                                    return @(
                                        (New-SPDscMockPrereq -Name "Microsoft CCR and DSS Runtime 2008 R3"),
                                        (New-SPDscMockPrereq -Name "Microsoft Sync Framework Runtime v1.0 SP1 (x64)"),
                                        (New-SPDscMockPrereq -Name "AppFabric 1.1 for Windows Server"),
                                        (New-SPDscMockPrereq -Name "WCF Data Services 5.6.0 Runtime"),
                                        (New-SPDscMockPrereq -Name "Microsoft Identity Extensions"),
                                        (New-SPDscMockPrereq -Name "Active Directory Rights Management Services Client 2.1"),
                                        (New-SPDscMockPrereq -Name "Microsoft SQL Server 2012 Native Client"),
                                        (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2017 Redistributable (x64) - 14.13.26020" -BundleUpgradeCode @("{C146EF48-4D31-3C3D-A2C5-1E91AF8A0A9B}") -DisplayVersion "14.13.26020.0")
                                    )
                                }
                            }
                            else
                            {
                                # SharePoint SE
                                Mock -CommandName Get-ItemProperty -ParameterFilter {
                                    $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                                } -MockWith {
                                    return @(
                                        (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2015-2019 Redistributable (x64)" -BundleUpgradeCode @("{C146EF48-4D31-3C3D-A2C5-1E91AF8A0A9B}") -DisplayVersion "14.29.30133.0")
                                    )
                                }
                            }
                        }
                        Default
                        {
                            throw [Exception] "A supported version of SharePoint was not used in testing"
                        }
                    }

                    Mock -CommandName Get-WindowsFeature -MockWith {
                        return @(@{
                                Name      = "ExampleFeature"
                                Installed = $true
                            })
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 16)
            {
                Context -Name "Microsoft Visual C++ 2015/2017 prerequisite is installed with lower version than required" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            IsSingleInstance = "Yes"
                            InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                            OnlineMode       = $true
                            Ensure           = "Present"
                        }

                        if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 10000)
                        {
                            # SharePoint 2016
                            Mock -CommandName Get-SPDscOSVersion -MockWith {
                                # SharePoint 2016
                                return @{
                                    Major = 10
                                    Build = 16000
                                }
                            }

                            Mock -CommandName Get-ItemProperty -ParameterFilter {
                                $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                            } -MockWith {
                                return @(
                                    (New-SPDscMockPrereq -Name "Microsoft CCR and DSS Runtime 2008 R3"),
                                    (New-SPDscMockPrereq -Name "Microsoft Sync Framework Runtime v1.0 SP1 (x64)"),
                                    (New-SPDscMockPrereq -Name "AppFabric 1.1 for Windows Server"),
                                    (New-SPDscMockPrereq -Name "WCF Data Services 5.6.0 Runtime"),
                                    (New-SPDscMockPrereq -Name "Microsoft ODBC Driver 11 for SQL Server"),
                                    (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2012 x64 Minimum Runtime - 11.0.61030"),
                                    (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2012 x64 Additional Runtime - 11.0.61030"),
                                    (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2015 Redistributable (x64) - 14.0.23026" -BundleUpgradeCode @("{C146EF48-4D31-3C3D-A2C5-1E91AF8A0A9B}") -DisplayVersion "14.0.0.0"),
                                    (New-SPDscMockPrereq -Name "Microsoft SQL Server 2012 Native Client"),
                                    (New-SPDscMockPrereq -Name "Active Directory Rights Management Services Client 2.1"),
                                    (New-SPDscMockPrereq -Name "Microsoft Identity Extensions")
                                )
                            }
                        }
                        else
                        {
                            # SharePoint 2019
                            Mock -CommandName Get-SPDscOSVersion -MockWith {
                                # SharePoint 2016
                                return @{
                                    Major = 10
                                    Build = 17763
                                }
                            }

                            Mock -CommandName Get-ItemProperty -ParameterFilter {
                                $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                            } -MockWith {
                                return @(
                                    (New-SPDscMockPrereq -Name "Microsoft CCR and DSS Runtime 2008 R3"),
                                    (New-SPDscMockPrereq -Name "Microsoft Sync Framework Runtime v1.0 SP1 (x64)"),
                                    (New-SPDscMockPrereq -Name "AppFabric 1.1 for Windows Server"),
                                    (New-SPDscMockPrereq -Name "WCF Data Services 5.6.0 Runtime"),
                                    (New-SPDscMockPrereq -Name "Microsoft Identity Extensions"),
                                    (New-SPDscMockPrereq -Name "Active Directory Rights Management Services Client 2.1"),
                                    (New-SPDscMockPrereq -Name "Microsoft SQL Server 2012 Native Client"),
                                    (New-SPDscMockPrereq -Name "Microsoft Visual C++ 2017 Redistributable (x64) - 14.13.26020" -BundleUpgradeCode @("{C146EF48-4D31-3C3D-A2C5-1E91AF8A0A9B}") -DisplayVersion "14.10.0.0")
                                )
                            }
                        }

                        Mock -CommandName Get-WindowsFeature -MockWith {
                            return @(@{
                                    Name      = "ExampleFeature"
                                    Installed = $true
                                })
                        }
                    }

                    It "Should return absent from the get method" {
                        (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                    }

                    It "Should return false from the test method" {
                        Test-TargetResource @testParams | Should -Be $false
                    }
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 15)
            {
                Context -Name "Prerequisites are installed and should be (with SQL 2012 native client for SP2013)" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            IsSingleInstance = "Yes"
                            InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                            OnlineMode       = $true
                            Ensure           = "Present"
                        }

                        Mock -CommandName Get-ItemProperty -ParameterFilter {
                            $Path -eq "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
                        } -MockWith {
                            return @(
                                (New-SPDscMockPrereq -Name "Microsoft CCR and DSS Runtime 2008 R3"),
                                (New-SPDscMockPrereq -Name "Microsoft Sync Framework Runtime v1.0 SP1 (x64)"),
                                (New-SPDscMockPrereq -Name "AppFabric 1.1 for Windows Server"),
                                (New-SPDscMockPrereq -Name "WCF Data Services 5.6.0 Runtime"),
                                (New-SPDscMockPrereq -Name "WCF Data Services 5.0 (for OData v3) Primary Components"),
                                (New-SPDscMockPrereq -Name "Microsoft SQL Server 2012 Native Client"),
                                (New-SPDscMockPrereq -Name "Active Directory Rights Management Services Client 2.0"),
                                (New-SPDscMockPrereq -Name "Microsoft Identity Extensions")
                            )
                        }

                        Mock -CommandName Get-WindowsFeature -MockWith {
                            return @(@{
                                    Name      = "ExampleFeature"
                                    Installed = $true
                                })
                        }
                    }

                    It "Should return present from the get method" {
                        (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                    }

                    It "Should return true from the test method" {
                        Test-TargetResource @testParams | Should -Be $true
                    }
                }
            }

            Context -Name "Prerequisites are installed but should not be" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $true
                        Ensure           = "Absent"
                    }
                }

                It "Should throw an exception from the set method" {
                    { Test-TargetResource @testParams } | Should -Throw
                }

                It "Should throw an exception from the set method" {
                    { Set-TargetResource @testParams } | Should -Throw
                }
            }

            Context -Name "Prerequisites are not installed but should be and are to be installed in offline mode" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $false
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-ItemProperty -MockWith {
                        return @()
                    } -ParameterFilter { $null -ne $Path }

                    Mock -CommandName Start-Process -MockWith {
                        return @{
                            ExitCode = 0
                        }
                    }
                    Mock -CommandName Test-Path -MockWith {
                        return $true
                    }
                }

                It "Should throw an exception in the set method if required parameters are not set" {
                    { Set-TargetResource @testParams } | Should -Throw
                }

                It "does not throw an exception where the required parameters are included" {
                    switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
                    {
                        15
                        {
                            $requiredParams = @("SQLNCli", "PowerShell", "NETFX", "IDFX", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "WCFDataServices", "KB2671763", "WCFDataServices56")
                        }
                        16
                        {
                            if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 10000)
                            {
                                # SharePoint 2016
                                $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNetFx", "MSVCRT11", "MSVCRT14", "ODBC")
                            }
                            elseif ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 13000)
                            {
                                # SharePoint 2019
                                $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNet472", "MSVCRT11", "MSVCRT141")
                            }
                            else
                            {
                                # SharePoint SE
                                $requiredParams = @("DotNet48", "MSVCRT142")
                            }
                        }
                        Default
                        {
                            throw [Exception] "A supported version of SharePoint was not used in testing"
                        }
                    }

                    $requiredParams | ForEach-Object -Process {
                        $testParams.Add($_, "C:\fake\value.exe")
                    }

                    { Set-TargetResource @testParams } | Should -Not -Throw
                }
            }

            Context -Name "Prerequisites are not installed but should be and are to be installed in offline mode with UNC path specified" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "\\server\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $false
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-ItemProperty -MockWith {
                        return @()
                    } -ParameterFilter { $null -ne $Path }

                    Mock -CommandName Get-Item -MockWith {
                        return $null
                    } -ParameterFilter { $Path.StartsWith("\\") }

                    Mock -CommandName Start-Process -MockWith {
                        return @{
                            ExitCode = 0
                        }
                    }
                    Mock -CommandName Test-Path -MockWith {
                        return $true
                    }
                }

                It "Should throw an exception in the set method if required parameters are not set" {
                    { Set-TargetResource @testParams } | Should -Throw
                }

                It "does not throw an exception where the required parameters are included" {
                    switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
                    {
                        15
                        {
                            $requiredParams = @("SQLNCli", "PowerShell", "NETFX", "IDFX", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "WCFDataServices", "KB2671763", "WCFDataServices56")
                        }
                        16
                        {
                            if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 10000)
                            {
                                # SharePoint 2016
                                $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNetFx", "MSVCRT11", "MSVCRT14", "ODBC")
                            }
                            elseif ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 13000)
                            {
                                # SharePoint 2019
                                $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNet472", "MSVCRT11", "MSVCRT141")
                            }
                            else
                            {
                                # SharePoint SE
                                $requiredParams = @("DotNet48", "MSVCRT142")
                            }
                        }
                        Default
                        {
                            throw [Exception] "A supported version of SharePoint was not used in testing"
                        }
                    }

                    $requiredParams | ForEach-Object -Process {
                        $testParams.Add($_, "C:\fake\value.exe")
                    }

                    { Set-TargetResource @testParams } | Should -Not -Throw
                }
            }

            Context -Name "Prerequisites are not installed but should be and are to be installed in offline mode from CDROM" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $false
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-ItemProperty -MockWith {
                        return @()
                    } -ParameterFilter { $null -ne $Path }

                    Mock -CommandName Get-Item -MockWith {
                        return $null
                    } -ParameterFilter { $Path.StartsWith("C:\") }

                    Mock -CommandName Get-Volume -MockWith {
                        return @{
                            DriveType = "CD-ROM"
                        }
                    }

                    Mock -CommandName Start-Process -MockWith {
                        return @{
                            ExitCode = 0
                        }
                    }
                    Mock -CommandName Test-Path -MockWith {
                        return $true
                    }

                    switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
                    {
                        15
                        {
                            $requiredParams = @("SQLNCli", "PowerShell", "NETFX", "IDFX", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "WCFDataServices", "KB2671763", "WCFDataServices56")
                        }
                        16
                        {
                            if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 10000)
                            {
                                # SharePoint 2016
                                $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNetFx", "MSVCRT11", "MSVCRT14", "ODBC")
                            }
                            elseif ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 13000)
                            {
                                # SharePoint 2019
                                $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNet472", "MSVCRT11", "MSVCRT141")
                            }
                            else
                            {
                                # SharePoint SE
                                $requiredParams = @("DotNet48", "MSVCRT142")
                            }
                        }
                        Default
                        {
                            throw [Exception] "A supported version of SharePoint was not used in testing"
                        }
                    }

                    $requiredParams | ForEach-Object -Process {
                        $testParams.Add($_, "C:\fake\value.exe")
                    }
                }

                It "does not throw an exception where the required parameters are included" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Get-Item -Times 0
                    Assert-MockCalled Start-Process
                }
            }

            Context -Name "Prerequisites are not installed but should be and are to be installed in offline mode, but invalid paths have been passed" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $false
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-WindowsFeature -MockWith {
                        return @( @{
                                Name      = "ExampleFeature"
                                Installed = $false
                            })
                    }

                    Mock -CommandName Get-ItemProperty -MockWith {
                        return @()
                    }

                    Mock -CommandName Start-Process -MockWith {
                        return @{
                            ExitCode = 0
                        }
                    }
                    Mock -CommandName Test-Path -MockWith {
                        return $false
                    }
                }

                It "Should throw an exception in the set method if required parameters are not set" {
                    { Set-TargetResource @testParams } | Should -Throw
                }

                It "does not throw an exception where the required parameters are included" {
                    switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
                    {
                        15
                        {
                            $requiredParams = @("SQLNCli", "PowerShell", "NETFX", "IDFX", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "WCFDataServices", "KB2671763", "WCFDataServices56")
                        }
                        16
                        {
                            $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNetFx", "MSVCRT11", "MSVCRT14", "ODBC")
                        }
                        Default
                        {
                            throw [Exception] "A supported version of SharePoint was not used in testing"
                        }
                    }
                    $requiredParams | ForEach-Object -Process {
                        $testParams.Add($_, "C:\fake\value.exe")
                    }

                    { Set-TargetResource @testParams } | Should -Throw
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 15)
            {
                Context -Name "SharePoint 2013 is installing on a server with .NET 4.6" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            IsSingleInstance = "Yes"
                            InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                            OnlineMode       = $true
                            Ensure           = "Present"
                        }

                        Mock -CommandName Get-ChildItem {
                            $full = @{
                                Version     = "4.6.0.0"
                                Release     = "0"
                                PSChildName = "Full"
                            }

                            $client = @{
                                Version     = "4.6.0.0"
                                Release     = "0"
                                PSChildName = "Client"
                            }

                            $returnval = @($full, $client)
                            $returnVal = $returnVal | Add-Member ScriptMethod GetValue { return 391000 } -PassThru
                            return $returnval
                        }

                        Mock -CommandName Get-ItemProperty -MockWith {
                            return @{
                                VersionInfo = @{
                                    FileVersion = "15.0.4600.1000"
                                }
                            }
                        } -ParameterFilter {
                            $Path -eq "C:\SPInstall\updates\svrsetup.dll"
                        }
                    }

                    It "throws an error in the set method" {
                        { Set-TargetResource @testParams } | Should -Throw ("A known issue prevents installation of SharePoint 2013 on " + `
                                "servers that have .NET 4.6 already installed")
                    }
                }

                Context -Name "SharePoint 2013 is installing on a server with .NET 4.6 with compatibility update" {
                    BeforeAll {
                        $testParams = @{
                            IsSingleInstance = "Yes"
                            InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                            OnlineMode       = $true
                            Ensure           = "Present"
                        }

                        Mock -CommandName Get-ChildItem {
                            $full = @{
                                Version     = "4.6.0.0"
                                Release     = "0"
                                PSChildName = "Full"
                            }

                            $client = @{
                                Version     = "4.6.0.0"
                                Release     = "0"
                                PSChildName = "Client"
                            }

                            $returnval = @($full, $client)
                            $returnVal = $returnVal | Add-Member ScriptMethod GetValue { return 391000 } -PassThru
                            return $returnval
                        }

                        Mock -CommandName Get-ItemProperty -MockWith {
                            return @{
                                VersionInfo = @{
                                    FileVersion = "15.0.4709.1000"
                                }
                            }
                        } -ParameterFilter {
                            $Path -eq "C:\SPInstall\updates\svrsetup.dll"
                        }
                    }

                    It "should install prereqs" {
                        Mock Start-Process { return @{ ExitCode = 0 } }
                        Mock Test-Path { return $true }

                        Set-TargetResource @testParams
                        Assert-MockCalled Start-Process -Scope It
                    }
                }
            }

            Context -Name "Prerequisites are not installed but should be and are to be installed in offline mode, with SXSstore specified" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $false
                        SXSpath          = "C:\SPInstall\SXS"
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-ItemProperty -MockWith {
                        return @()
                    }

                    Mock -CommandName Start-Process -MockWith {
                        return @{
                            ExitCode = 0
                        }
                    }

                    Mock -CommandName Test-Path -MockWith {
                        return $true
                    }

                    switch ($Global:SPDscHelper.CurrentStubBuildNumber.Major)
                    {
                        15
                        {
                            $requiredParams = @("SQLNCli", "PowerShell", "NETFX", "IDFX", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "WCFDataServices", "KB2671763", "WCFDataServices56")
                        }
                        16
                        {
                            $requiredParams = @("SQLNCli", "Sync", "AppFabric", "IDFX11", "MSIPCClient", "KB3092423", "WCFDataServices56", "DotNetFx", "MSVCRT11", "MSVCRT14", "ODBC")
                        }
                        Default
                        {
                            throw [Exception] "A supported version of SharePoint was not used in testing"
                        }
                    }
                    $requiredParams | ForEach-Object -Process {
                        $testParams.Add($_, "C:\fake\value.exe")
                    }
                }

                It "installs required Windows features from specified path" {
                    Mock -CommandName Install-WindowsFeature -MockWith {
                        return @( @{
                                Name          = "ExampleFeature"
                                Success       = $true
                                RestartNeeded = "No"
                            })
                    }

                    Set-TargetResource @testParams
                    Assert-MockCalled Install-WindowsFeature
                }

                It "feature install requires a reboot" {
                    Mock -CommandName Install-WindowsFeature -MockWith {
                        return @( @{
                                Name          = "ExampleFeature"
                                Success       = $true
                                RestartNeeded = "Yes"
                            })
                    }

                    Set-TargetResource @testParams
                    $global:DSCMachineStatus | Should -Be 1
                }

                It "feature install failure throws an error" {
                    Mock -CommandName Install-WindowsFeature -MockWith {
                        return @( @{
                                Name          = "ExampleFeature"
                                Success       = $false
                                RestartNeeded = "No"
                            })
                    }

                    { Set-TargetResource @testParams } | Should -Throw "Error installing ExampleFeature"
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 16)
            {
                Context -Name "Unsupported OS is used" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            IsSingleInstance = "Yes"
                            InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                            OnlineMode       = $true
                            Ensure           = "Present"
                        }

                        Mock -CommandName Get-SPDscOSVersion -MockWith {
                            if ($Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 10000)
                            {
                                # SharePoint 2016
                                return @{
                                    Major = 6
                                    Minor = 2
                                }
                            }
                            else
                            {
                                # SharePoint 2019
                                return @{
                                    Major = 6
                                    Minor = 3
                                }
                            }
                        }
                    }

                    It "Should throw an exception from the get method" {
                        { Get-TargetResource @testParams } | Should -Throw
                    }

                    It "Should throw an exception from the test method" {
                        { Test-TargetResource @testParams } | Should -Throw
                    }

                    It "Should throw an exception from the set method" {
                        { Set-TargetResource @testParams } | Should -Throw
                    }
                }
            }

            Context -Name "InstallerPath does not exist" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $true
                        Ensure           = "Present"
                    }

                    Mock -CommandName Test-Path {
                        return $false
                    }
                }

                It "throws an error in the get method" {
                    { Get-TargetResource @testParams } | Should -Throw ("PrerequisitesInstaller cannot be found")
                }

                It "throws an error in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw ("PrerequisitesInstaller cannot be found")
                }

                It "throws an error in the test method" {
                    { Test-TargetResource @testParams } | Should -Throw ("PrerequisitesInstaller cannot be found")
                }
            }

            Context -Name "InstallerPath is blocked" -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = "Yes"
                        InstallerPath    = "C:\SPInstall\Prerequisiteinstaller.exe"
                        OnlineMode       = $true
                        Ensure           = "Present"
                    }

                    Mock -CommandName Get-Item {
                        return "data"
                    }
                }

                It "throws an error in the get method" {
                    { Get-TargetResource @testParams } | Should -Throw ("PrerequisitesInstaller is blocked!")
                }

                It "throws an error in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw ("PrerequisitesInstaller is blocked!")
                }

                It "throws an error in the test method" {
                    { Test-TargetResource @testParams } | Should -Throw ("PrerequisitesInstaller is blocked!")
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 15)
            {
                Context -Name "Running ReverseDsc Export" -Fixture {
                    BeforeAll {
                        Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                        Mock -CommandName Write-Host -MockWith { }

                        Mock -CommandName Get-TargetResource -MockWith {
                            return @{
                                IsSingleInstance  = "Yes"
                                InstallerPath     = "C:\SPInstall\Prerequisiteinstaller.exe"
                                OnlineMode        = $false
                                SXSpath           = "c:\SPInstall\Windows2012r2-SXS"
                                SQLNCli           = "C:\SPInstall\prerequisiteinstallerfiles\sqlncli.msi"
                                PowerShell        = "C:\SPInstall\prerequisiteinstallerfiles\Windows6.1-KB2506143-x64.msu"
                                NETFX             = "C:\SPInstall\prerequisiteinstallerfiles\dotNetFx45_Full_setup.exe"
                                IDFX              = "C:\SPInstall\prerequisiteinstallerfiles\Windows6.1-KB974405-x64.msu"
                                Sync              = "C:\SPInstall\prerequisiteinstallerfiles\Synchronization.msi"
                                AppFabric         = "C:\SPInstall\prerequisiteinstallerfiles\WindowsServerAppFabricSetup_x64.exe"
                                IDFX11            = "C:\SPInstall\prerequisiteinstallerfiles\MicrosoftIdentityExtensions-64.msi"
                                MSIPCClient       = "C:\SPInstall\prerequisiteinstallerfiles\setup_msipc_x64.msi"
                                WCFDataServices   = "C:\SPInstall\prerequisiteinstallerfiles\WcfDataServices.exe"
                                KB2671763         = "C:\SPInstall\prerequisiteinstallerfiles\AppFabric1.1-RTM-KB2671763-x64-ENU.exe"
                                WCFDataServices56 = "C:\SPInstall\prerequisiteinstallerfiles\WcfDataServices56.exe"
                            }
                        }

                        if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                        {
                            $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                            $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                        }

                        if ($null -eq (Get-Variable -Name 'DynamicCompilation' -ErrorAction SilentlyContinue))
                        {
                            $Global:DynamicCompilation = $true
                        }

                        $result = @'
        if ($ConfigurationData.NonNodeData.FullInstallation)
        {
            SPInstallPrereqs PrerequisitesInstallation
            {
                InstallerPath = $ConfigurationData.NonNodeData.SPPrereqsInstallerPath;
                OnlineMode = $True;
                Ensure = "Present";
                IsSingleInstance = "Yes";
                PSDscRunAsCredential = $Credsspfarm;
            }
        }

'@
                    }

                    It "Should return valid DSC block from the Export method" {
                        Export-TargetResource | Should -Be $result
                    }
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
