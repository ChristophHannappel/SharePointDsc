[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPWebApplicationExtension'
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

                try
                {
                    [Microsoft.SharePoint.Administration.SPUrlZone]
                }
                catch
                {
                    Add-Type -TypeDefinition @"
        namespace Microsoft.SharePoint.Administration {
            public enum SPUrlZone { Default, Intranet, Internet, Custom, Extranet };
        }
"@
                }

                # Mocks for all contexts
                Mock -CommandName New-SPAuthenticationProvider -MockWith { }
                Mock -CommandName New-SPWebApplicationExtension -MockWith { }
                Mock -CommandName Remove-SPWebApplication -MockWith { }
                Mock -CommandName Get-SPTrustedIdentityTokenIssuer -MockWith { }
                Mock -CommandName Set-SPWebApplication -MockWith { }

                Mock -CommandName Get-SPDscOSVersion -MockWith {
                    return @{
                        Major = 10
                        Minor = 0
                        Build = 17763
                    }
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
            Context -Name "AllowLegacyEncryption used with other OS than Windows Server 2022" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl             = "http://nosuchwebapplication.sharepoint.com"
                        Name                  = "Intranet Zone"
                        Url                   = "http://intranet.sharepoint.com"
                        Zone                  = "Intranet"
                        AllowLegacyEncryption = $true
                        Ensure                = "Present"
                    }

                    Mock -CommandName Get-SPDscOSVersion -MockWith {
                        return @{
                            Major = 10
                            Minor = 0
                            Build = 17763
                        }
                    }
                }

                It "return AllowLegacyEncryption=Null from the get method" {
                    (Get-TargetResource @testParams).AllowLegacyEncryption | Should -BeNullOrEmpty
                }

                It "retrieving Managed Account fails in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "You cannot specify the AllowLegacyEncryption parameter when using Windows Server 2019 or earlier."
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 16 -and
                $Global:SPDscHelper.CurrentStubBuildNumber.Build -gt 10000 -and
                $Global:SPDscHelper.CurrentStubBuildNumber.Build -lt 13000)
            {
                Context -Name "AllowLegacyEncryption used with SharePoint 2019" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl               = "http://nosuchwebapplication.sharepoint.com"
                            Name                    = "Intranet Zone"
                            Url                     = "http://intranet.sharepoint.com"
                            Zone                    = "Intranet"
                            UseServerNameIndication = $true
                            Ensure                  = "Present"
                        }
                    }

                    It "return UseServerNameIndication=Null from the get method" {
                        (Get-TargetResource @testParams).UseServerNameIndication | Should -BeNullOrEmpty
                    }

                    It "retrieving Managed Account fails in the set method" {
                        { Set-TargetResource @testParams } | Should -Throw "The parameters AllowLegacyEncryption, CertificateThumbprint or UseServerNameIndication are only supported with SharePoint Server Subscription Edition."
                    }
                }
            }

            Context -Name "The parent web application does not exist" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl = "http://nosuchwebapplication.sharepoint.com"
                        Name      = "Intranet Zone"
                        Url       = "http://intranet.sharepoint.com"
                        Zone      = "Intranet"
                        Ensure    = "Present"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith { return $null }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "retrieving non-existent web application fails in the set method" {
                    { Set-TargetResource @testParams } | Should -Throw "Web Application with URL $($testParams.WebAppUrl) does not exist"
                }
            }

            Context -Name "The web application extension that uses NTLM authentication doesn't exist but should" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl = "http://company.sharepoint.com"
                        Name      = "Intranet Zone"
                        Url       = "http://intranet.sharepoint.com"
                        Zone      = "Intranet"
                        Ensure    = "Present"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        return @{
                            DisplayName = "Company SharePoint"
                            URL         = "http://company.sharepoint.com"
                            IISSettings = @()
                        }
                    }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the new cmdlet from the set method" {
                    Set-TargetResource @testParams

                    Assert-MockCalled New-SPWebApplicationExtension
                }

                It "Should call the new cmdlet from the set where anonymous authentication is requested" {
                    $testParams.Add("AllowAnonymous", $true)
                    Set-TargetResource @testParams

                    Assert-MockCalled New-SPWebApplicationExtension
                }
            }

            Context -Name "The web application extension that uses Kerberos doesn't exist but should" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl = "http://company.sharepoint.com"
                        Name      = "Intranet Zone"
                        Url       = "http://intranet.sharepoint.com"
                        Zone      = "Intranet"
                        Ensure    = "Present"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        return @{
                            DisplayName = "Company SharePoint"
                            URL         = "http://company.sharepoint.com"
                            IISSettings = @()
                        }
                    }
                }

                It "Should return absent from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should call the new cmdlet from the set method" {
                    Set-TargetResource @testParams

                    Assert-MockCalled New-SPWebApplicationExtension
                }
            }

            Context -Name "The web application extension does exist and should use NTLM without AllowAnonymous" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl  = "http://company.sharepoint.com"
                        Name       = "Intranet Zone"
                        Url        = "http://intranet.sharepoint.com"
                        HostHeader = "intranet.sharepoint.com"
                        Zone       = "Intranet"
                        Ensure     = "Present"
                    }

                    Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                        return @{
                            DisplayName     = "Windows Authentication"
                            DisableKerberos = $true
                        }
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 80
                                }
                                AllowAnonymous = $false
                            }
                        )

                        return (
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = $IISSettings
                            } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                        )
                    }

                    Mock -CommandName Get-SPAlternateUrl -MockWith {
                        return @{
                            PublicURL = $testParams.Url
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return AllowAnonymous False from the get method" {
                    (Get-TargetResource @testParams).AllowAnonymous | Should -Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web application extension does exist and should use NTLM without AllowAnonymous and with HTTPS" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl  = "http://company.sharepoint.com"
                        Name       = "Intranet Zone"
                        Url        = "https://intranet.sharepoint.com"
                        HostHeader = "intranet.sharepoint.com"
                        Zone       = "Intranet"
                        Ensure     = "Present"
                    }

                    Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                        return @{
                            DisplayName     = "Windows Authentication"
                            DisableKerberos = $true
                        }
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 443
                                }
                                ServerBindings = @{ }
                                AllowAnonymous = $false
                            })

                        return (
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = $IISSettings
                            } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                        )
                    }

                    Mock -CommandName Get-SPAlternateUrl -MockWith {
                        return @{
                            PublicURL = $testParams.Url
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return AllowAnonymous False from the get method" {
                    (Get-TargetResource @testParams).AllowAnonymous | Should -Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web application extension does exist and should use NTLM and AllowAnonymous" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl  = "http://company.sharepoint.com"
                        Name       = "Intranet Zone"
                        Url        = "http://intranet.sharepoint.com"
                        HostHeader = "intranet.sharepoint.com"
                        Zone       = "Intranet"
                        Ensure     = "Present"
                    }

                    Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                        return @{
                            DisplayName     = "Windows Authentication"
                            DisableKerberos = $true
                            AllowAnonymous  = $true
                        }
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 80
                                }
                                AllowAnonymous = $true
                            })

                        return (
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = $IISSettings
                            } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                        )
                    }

                    Mock -CommandName Get-SPAlternateUrl -MockWith {
                        return @{
                            PublicURL = $testParams.Url
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return AllowAnonymous True from the get method" {
                    (Get-TargetResource @testParams).AllowAnonymous | Should -Be $true
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web application extension does exist and should use Kerberos without AllowAnonymous" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl  = "http://company.sharepoint.com"
                        Name       = "Intranet Zone"
                        Url        = "http://intranet.sharepoint.com"
                        HostHeader = "intranet.sharepoint.com"
                        Zone       = "Intranet"
                        Ensure     = "Present"
                    }

                    Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                        return @{
                            DisplayName     = "Windows Authentication"
                            DisableKerberos = $false
                        }
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 80
                                }
                                AllowAnonymous = $false
                            })

                        return (
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = $IISSettings
                            } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                        )
                    }

                    Mock -CommandName Get-SPAlternateUrl -MockWith {
                        return @{
                            PublicURL = $testParams.Url
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return AllowAnonymous False from the get method" {
                    (Get-TargetResource @testParams).AllowAnonymous | Should -Be $false
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web application extension does exist and should use Kerberos and AllowAnonymous" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl  = "http://company.sharepoint.com"
                        Name       = "Intranet Zone"
                        Url        = "http://intranet.sharepoint.com"
                        HostHeader = "intranet.sharepoint.com"
                        Zone       = "Intranet"
                        Ensure     = "Present"
                    }

                    Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                        return @{
                            DisplayName     = "Windows Authentication"
                            DisableKerberos = $false
                            AllowAnonymous  = $true
                        }
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 80
                                }
                                AllowAnonymous = $true
                            })

                        return (
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = $IISSettings
                            } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                        )
                    }

                    Mock -CommandName Get-SPAlternateUrl -MockWith {
                        return @{
                            PublicURL = $testParams.Url
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return AllowAnonymous True from the get method" {
                    (Get-TargetResource @testParams).AllowAnonymous | Should -Be $true
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            Context -Name "The web application extension does exist and should with mismatched AllowAnonymous" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl      = "http://company.sharepoint.com"
                        Name           = "Intranet Zone"
                        Url            = "http://intranet.sharepoint.com"
                        HostHeader     = "intranet.sharepoint.com"
                        Zone           = "Intranet"
                        AllowAnonymous = $true
                        Ensure         = "Present"
                    }

                    Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                        return @{
                            DisplayName     = "Windows Authentication"
                            DisableKerberos = $true
                        }
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 80
                                }
                                Path           = "C:\Inetpub\wwwroot"
                                AllowAnonymous = $false
                            })

                        return (
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = $IISSettings
                            } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                        )
                    }

                    Mock -CommandName Get-SPAlternateUrl -MockWith {
                        return @{
                            PublicURL = $testParams.Url
                        }
                    }
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return AllowAnonymous False from the get method" {
                    (Get-TargetResource @testParams).AllowAnonymous | Should -Be $false
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update the web application extension settings in the set method" {
                    $Global:WebAppUpdateCalled = $false
                    Set-TargetResource @testParams
                    $Global:WebAppUpdateCalled | Should -Be $true
                }
            }

            Context -Name "The web application extension exists but shouldn't" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl = "http://company.sharepoint.com"
                        Name      = "Intranet Zone"
                        Url       = "http://intranet.sharepoint.com"
                        Zone      = "Intranet"
                        Ensure    = "Absent"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {
                        $IISSettings = @(
                            @{ }
                            @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.sharepoint.com"
                                    Port       = 80
                                }
                            })

                        return @{
                            DisplayName = "Company SharePoint"
                            URL         = "http://company.sharepoint.com"
                            IISSettings = $IISSettings
                        }
                    }
                }

                It "Should return present from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should remove the web application in the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPWebApplication
                }
            }

            Context -Name "A web application extension doesn't exist and shouldn't" -Fixture {
                BeforeAll {
                    $testParams = @{
                        WebAppUrl = "http://company.sharepoint.com"
                        Name      = "Intranet Zone"
                        Url       = "http://intranet.sharepoint.com"
                        Zone      = "Intranet"
                        Ensure    = "Absent"
                    }

                    Mock -CommandName Get-SPWebapplication -MockWith {

                        return @{
                            DisplayName = "Company SharePoint"
                            URL         = "http://company.sharepoint.com"
                            IISSettings = @()
                        }
                    }
                }

                It "Should return absent from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should -Be "Absent"
                }

                It "Should return true from the test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }
            }

            if ($Global:SPDscHelper.CurrentStubBuildNumber.Major -eq 16 -and
                $Global:SPDscHelper.CurrentStubBuildNumber.Build -gt 13000)
            {
                Context -Name "The web application extension doesn't exist but should (SPSE)" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl               = "http://company.sharepoint.com"
                            Name                    = "Intranet Zone"
                            Url                     = "https://intranet.sharepoint.com"
                            Zone                    = "Intranet"
                            HostHeader              = "intranet.sharepoint.com"
                            AllowLegacyEncryption   = $true
                            CertificateThumbprint   = '7CF9E91F141FCA1049F56AB96BE2A1D7D3F9198D'
                            UseServerNameIndication = $false
                            Path                    = "C:\inetpub\wwwroot\something"
                            Ensure                  = "Present"
                        }

                        Mock -CommandName Get-SPWebapplication -MockWith {
                            return @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = @()
                            }
                        }

                        Mock -CommandName Get-SPDscOSVersion -MockWith {
                            return @{
                                Major = 10
                                Minor = 0
                                Build = 20348
                            }
                        }

                        Mock -CommandName Get-SPCertificate -MockWith {
                            return @{
                                Thumbprint = $testParams.CertificateThumbprint
                            }
                        }
                    }

                    It "Should return absent from the get method" {
                        $result = Get-TargetResource @testParams
                        $result.Ensure | Should -Be "Absent"
                    }

                    It "Should return false from the test method" {
                        Test-TargetResource @testParams | Should -Be $false
                    }

                    It "Should call the new cmdlet from the set method" {
                        Set-TargetResource @testParams
                        Assert-MockCalled New-SPWebApplicationExtension
                    }
                }

                Context -Name "The specified certificate does not exist in CertMgmt for web extension (SPSE)" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl               = "http://company.sharepoint.com"
                            Name                    = "Intranet Zone"
                            Url                     = "https://intranet.sharepoint.com"
                            Zone                    = "Intranet"
                            AllowLegacyEncryption   = $true
                            CertificateThumbprint   = '7CF9E91F141FCA1049F56AB96BE2A1D7D3F9198D'
                            UseServerNameIndication = $false
                            Ensure                  = "Present"
                        }

                        Mock -CommandName Get-SPWebapplication -MockWith {
                            return @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://company.sharepoint.com"
                                IISSettings = @()
                            }
                        }

                        Mock -CommandName Get-SPDscOSVersion -MockWith {
                            return @{
                                Major = 10
                                Minor = 0
                                Build = 20348
                            }
                        }

                        Mock -CommandName Get-SPCertificate -MockWith {
                            return $null
                        }
                    }

                    It "Should throw an exception from the set method" {
                        { Set-TargetResource @testParams } | Should -Throw "No certificate found with the specified thumbprint: $($testParams.CertificateThumbprint). Make sure the certificate is added to Certificate Management first!"
                    }
                }

                Context -Name "The web application extension does exist but has mismatched Certificate settings (SPSE)" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl               = "http://company.sharepoint.com"
                            Name                    = "Intranet Zone"
                            Url                     = "https://intranet.sharepoint.com"
                            HostHeader              = "intranet.sharepoint.com"
                            Zone                    = "Intranet"
                            AllowLegacyEncryption   = $true
                            CertificateThumbprint   = '7CF9E91F141FCA1049F56AB96BE2A1D7D3F9198D'
                            UseServerNameIndication = $false
                            Ensure                  = "Present"
                        }

                        Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                            return @{
                                DisplayName     = "Windows Authentication"
                                DisableKerberos = $true
                            }
                        }

                        Mock -CommandName Get-SPWebapplication -MockWith {
                            $IISSettings = @(
                                @{ }
                                @{
                                    SecureBindings = @{ }
                                    ServerBindings = @{
                                        HostHeader = "intranet.sharepoint.com"
                                        Port       = 80
                                    }
                                    Path           = "C:\Inetpub\wwwroot"
                                    AllowAnonymous = $false
                                })

                            return (
                                @{
                                    DisplayName = "Company SharePoint"
                                    URL         = "http://company.sharepoint.com"
                                    IISSettings = $IISSettings
                                } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                            )
                        }

                        Mock -CommandName Get-SPAlternateUrl -MockWith {
                            return @{
                                PublicURL = $testParams.Url
                            }
                        }

                        Mock -CommandName Get-SPDscOSVersion -MockWith {
                            return @{
                                Major = 10
                                Minor = 0
                                Build = 20348
                            }
                        }

                        Mock -CommandName Get-SPCertificate -MockWith {
                            return @{
                                Thumbprint = $testParams.CertificateThumbprint
                            }
                        }
                    }

                    It "Should return present from the get method" {
                        (Get-TargetResource @testParams).Ensure | Should -Be "Present"
                    }

                    It "Should return false from the test method" {
                        Test-TargetResource @testParams | Should -Be $false
                    }

                    It "Should update the web application extension settings in the set method" {
                        Set-TargetResource @testParams
                        Assert-MockCalled -CommandName Set-SPWebApplication
                    }
                }

                Context -Name "The specified certificate does not exist in CertMgmt for existing extension (SPSE)" -Fixture {
                    BeforeAll {
                        $testParams = @{
                            WebAppUrl               = "http://company.sharepoint.com"
                            Name                    = "Intranet Zone"
                            Url                     = "https://intranet.sharepoint.com"
                            HostHeader              = "intranet.sharepoint.com"
                            Zone                    = "Intranet"
                            AllowLegacyEncryption   = $true
                            CertificateThumbprint   = '7CF9E91F141FCA1049F56AB96BE2A1D7D3F9198D'
                            UseServerNameIndication = $false
                            Ensure                  = "Present"
                        }

                        Mock -CommandName Get-SPAuthenticationProvider -MockWith {
                            return @{
                                DisplayName     = "Windows Authentication"
                                DisableKerberos = $true
                            }
                        }

                        Mock -CommandName Get-SPWebapplication -MockWith {
                            $IISSettings = @(
                                @{ }
                                @{
                                    SecureBindings = @{ }
                                    ServerBindings = @{
                                        HostHeader = "intranet.sharepoint.com"
                                        Port       = 80
                                    }
                                    Path           = "C:\Inetpub\wwwroot"
                                    AllowAnonymous = $false
                                })

                            return (
                                @{
                                    DisplayName = "Company SharePoint"
                                    URL         = "http://company.sharepoint.com"
                                    IISSettings = $IISSettings
                                } | Add-Member ScriptMethod Update { $Global:WebAppUpdateCalled = $true } -PassThru
                            )
                        }

                        Mock -CommandName Get-SPAlternateUrl -MockWith {
                            return @{
                                PublicURL = $testParams.Url
                            }
                        }

                        Mock -CommandName Get-SPDscOSVersion -MockWith {
                            return @{
                                Major = 10
                                Minor = 0
                                Build = 20348
                            }
                        }

                        Mock -CommandName Get-SPCertificate -MockWith {
                            return $null
                        }
                    }

                    It "Should throw an exception from the set method" {
                        { Set-TargetResource @testParams } | Should -Throw "No certificate found with the specified thumbprint: $($testParams.CertificateThumbprint). Make sure the certificate is added to Certificate Management first!"
                    }
                }
            }

            Context -Name "Running ReverseDsc Export" -Fixture {
                BeforeAll {
                    Import-Module (Join-Path -Path (Split-Path -Path (Get-Module SharePointDsc -ListAvailable).Path -Parent) -ChildPath "Modules\SharePointDSC.Reverse\SharePointDSC.Reverse.psm1")

                    Mock -CommandName Write-Host -MockWith { }

                    Mock -CommandName Get-TargetResource -MockWith {
                        return @{
                            WebAppUrl      = "http://example.contoso.local"
                            Name           = "Contoso Intranet Zone"
                            AllowAnonymous = $false
                            Url            = "http://intranet.contoso.local"
                            Zone           = "Intranet"
                            HostHeader     = "intranet.contoso.local"
                            Path           = "c:\inetpub\wwwroot\wss\VirtualDirectories\intranet"
                            UseSSL         = $false
                            Port           = 80
                            Ensure         = "Present"
                        }
                    }

                    Mock -CommandName Get-SPWebApplication -MockWith {
                        $IISSettings = @{
                            Intranet = @{
                                SecureBindings = @{ }
                                ServerBindings = @{
                                    HostHeader = "intranet.contoso.local"
                                    Port       = 80
                                }
                            }
                        }

                        return @(
                            @{
                                DisplayName = "Company SharePoint"
                                URL         = "http://example.contoso.local"
                                IISSettings = $IISSettings
                            }
                        )
                    }

                    if ($null -eq (Get-Variable -Name 'spFarmAccount' -ErrorAction SilentlyContinue))
                    {
                        $mockPassword = ConvertTo-SecureString -String "password" -AsPlainText -Force
                        $Global:spFarmAccount = New-Object -TypeName System.Management.Automation.PSCredential ("contoso\spfarm", $mockPassword)
                    }

                    $result = @'
        SPWebApplicationExtension [0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12}
        {
            AllowAnonymous       = \$False;
            Ensure               = "Present";
            HostHeader           = "intranet.contoso.local";
            Name                 = "Contoso Intranet Zone";
            Path                 = "c:\\inetpub\\wwwroot\\wss\\VirtualDirectories\\intranet";
            Port                 = 80;
            PsDscRunAsCredential = \$Credsspfarm;
            Url                  = "http://intranet.contoso.local";
            UseSSL               = \$False;
            WebAppUrl            = "http://example.contoso.local";
            Zone                 = "Intranet";
        }

'@
                }

                It "Should return valid DSC block from the Export method" {
                    Export-TargetResource | Should -Match $result
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
