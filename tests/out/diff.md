# MSI package comparison

**Verdict: the packages differ.**

Report generated: 2026-09-25 23:15:19

| | Reference (left) | Difference (right) |
| --- | --- | --- |
| File | DemoApp-1.0.msi | DemoApp-1.1.msi |
| Path | E:\Cursor\msi-diff\tests\out\DemoApp-1.0.msi | E:\Cursor\msi-diff\tests\out\DemoApp-1.1.msi |
| Size, bytes | 20,480 | 20,480 |
| Modified | 2026-09-25 23:15:04 | 2026-09-25 23:15:05 |
| SHA-256 | 95df222a0de2562a0f7ce5df2bdb7c190c68e8aecbeb69e925b2fe8715c06519 | e1fbf93d07bace057015f769b9c70dca53298f136133e9799b72a5c58be49693 |

## Change summary

| Metric | Value |
| --- | --- |
| Tables added / removed / changed | 1 / 0 / 9 |
| Tables unchanged | 3 |
| Rows added / removed / changed | 8 / 5 / 7 |
| Properties added / removed / changed | 1 / 1 / 3 |
| Files added / removed / changed | 1 / 1 / 1 |
| Summary Information fields changed | 4 |

## Summary Information Stream

_Package metadata: package code, platform, languages, schema version_

| Status | Name | DemoApp-1.0.msi | DemoApp-1.1.msi |
| --- | --- | --- | --- |
| ~ changed | `Comments` | Test package Demo App 1.0.0 | Test package Demo App 1.1.0 |
| ~ changed | `Template` | Intel;1033 | x64;1033 |
| ~ changed | `PackageCode` | {B1111111-1111-1111-1111-111111111111} | {B2222222-2222-2222-2222-222222222222} |
| ~ changed | `Template.Platform` | Intel | x64 |

## Property table

_ProductCode, ProductVersion, UpgradeCode and the other installer properties_

| Status | Name | DemoApp-1.0.msi | DemoApp-1.1.msi |
| --- | --- | --- | --- |
| - removed | `LEGACYMODE` | 1 |  |
| ~ changed | `Manufacturer` | Contoso Ltd | Contoso International Ltd |
| ~ changed | `ProductCode` | {A1111111-1111-1111-1111-111111111111} | {A2222222-2222-2222-2222-222222222222} |
| ~ changed | `ProductVersion` | 1.0.0 | 1.1.0 |
| + added | `REBOOT` |  | ReallySuppress |

## Installed files

_File + Component + Directory flattened into target paths. MD5 comes from the MsiFileHash table._

### Files - +1 / -1 / ~1

Match key: `TargetPath`

| Status | TargetPath | Version | Size | MD5 | Language | Attributes | Sequence | Component | ComponentId |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| - removed | TARGETDIR\ProgramFilesFolder\Contoso\DemoApp\legacy.dll | 1.0.0.0 | 33792 | (null) | 1033 | 512 | 3 | MainExe | {11111111-1111-1111-1111-111111111111} |
| + added | TARGETDIR\ProgramFilesFolder\Contoso\DemoApp\plugin.dll | 1.1.0.0 | 51200 | (null) | 1033 | 512 | 3 | Plugin | {33333333-3333-3333-3333-333333333333} |
| ~ changed | TARGETDIR\ProgramFilesFolder\Contoso\DemoApp\app.exe | **1.0.0.0** -> **1.1.0.0** | **204800** -> **215040** | **e8030000d0070000b80b0000a00f0000** -> **581b0000b036000008520000606d0000** | 1033 | 512 | 1 | MainExe | {11111111-1111-1111-1111-111111111111} |

## MSI database tables

| Status | Table | + | - | ~ | = | Rows left | Rows right |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| + added | `LaunchCondition` | 1 | 0 | 0 | 0 | 0 | 1 |
| ~ changed | `Binary` | 0 | 0 | 1 | 0 | 1 | 1 |
| ~ changed | `Component` | 1 | 0 | 0 | 2 | 2 | 3 |
| ~ changed | `CustomAction` | 1 | 0 | 0 | 1 | 1 | 2 |
| ~ changed | `FeatureComponents` | 1 | 0 | 0 | 2 | 2 | 3 |
| ~ changed | `File` | 1 | 1 | 1 | 1 | 3 | 3 |
| ~ changed | `MsiFileHash` | 0 | 0 | 1 | 1 | 2 | 2 |
| ~ changed | `Property` | 1 | 1 | 3 | 4 | 8 | 8 |
| ~ changed | `Registry` | 0 | 1 | 1 | 1 | 3 | 2 |
| ~ changed | `Upgrade` | 2 | 2 | 0 | 0 | 2 | 2 |
| = unchanged | `Directory` | 0 | 0 | 0 | 4 | 4 | 4 |
| = unchanged | `Feature` | 0 | 0 | 0 | 1 | 1 | 1 |
| = unchanged | `Media` | 0 | 0 | 0 | 1 | 1 | 1 |

### Row-level differences

<details>
<summary><b>LaunchCondition - +1 / -0 / ~0</b></summary>

Match key: `Condition`

| Status | Condition | Description |
| --- | --- | --- |
| + added | VersionNT >= 601 | Windows 7 or newer is required. |

</details>

<details>
<summary><b>Binary - +0 / -0 / ~1</b></summary>

Match key: `Name`

| Status | Name | Data |
| --- | --- | --- |
| ~ changed | Setup | **[stream: 25 bytes; sha256=83d4da89c4f57829]** -> **[stream: 42 bytes; sha256=55713d0c484e73a4]** |

</details>

<details>
<summary><b>Component - +1 / -0 / ~0</b></summary>

Match key: `Component`

| Status | Component | ComponentId | Directory_ | Attributes | Condition | KeyPath |
| --- | --- | --- | --- | --- | --- | --- |
| + added | Plugin | {33333333-3333-3333-3333-333333333333} | INSTALLDIR | 0 | (null) | plugin.dll |

</details>

<details>
<summary><b>CustomAction - +1 / -0 / ~0</b></summary>

Match key: `Action`

| Status | Action | Type | Source | Target |
| --- | --- | --- | --- | --- |
| + added | RegisterPlugin | 1 | Setup | RegisterPluginEntry |

</details>

<details>
<summary><b>FeatureComponents - +1 / -0 / ~0</b></summary>

Match key: `Feature_, Component_`

| Status | Feature_ | Component_ |
| --- | --- | --- |
| + added | Complete | Plugin |

</details>

<details>
<summary><b>File - +1 / -1 / ~1</b></summary>

Match key: `File`

| Status | File | Component_ | FileName | FileSize | Version | Language | Attributes | Sequence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| - removed | legacy.dll | MainExe | legacy.dll | 33792 | 1.0.0.0 | 1033 | 512 | 3 |
| + added | plugin.dll | Plugin | plugin.dll | 51200 | 1.1.0.0 | 1033 | 512 | 3 |
| ~ changed | app.exe | MainExe | app.exe | **204800** -> **215040** | **1.0.0.0** -> **1.1.0.0** | 1033 | 512 | 1 |

</details>

<details>
<summary><b>MsiFileHash - +0 / -0 / ~1</b></summary>

Match key: `File_`

| Status | File_ | Options | HashPart1 | HashPart2 | HashPart3 | HashPart4 |
| --- | --- | --- | --- | --- | --- | --- |
| ~ changed | app.exe | 0 | **1000** -> **7000** | **2000** -> **14000** | **3000** -> **21000** | **4000** -> **28000** |

</details>

<details>
<summary><b>Property - +1 / -1 / ~3</b></summary>

Match key: `Property`

| Status | Property | Value |
| --- | --- | --- |
| - removed | LEGACYMODE | 1 |
| + added | REBOOT | ReallySuppress |
| ~ changed | ProductVersion | **1.0.0** -> **1.1.0** |
| ~ changed | ProductCode | **{A1111111-1111-1111-1111-111111111111}** -> **{A2222222-2222-2222-2222-222222222222}** |
| ~ changed | Manufacturer | **Contoso Ltd** -> **Contoso International Ltd** |

</details>

<details>
<summary><b>Registry - +0 / -1 / ~1</b></summary>

Match key: `Registry`

| Status | Registry | Root | Key | Name | Value | Component_ |
| --- | --- | --- | --- | --- | --- | --- |
| - removed | RegLegacy | 2 | SOFTWARE\Contoso\DemoApp | LegacyMode | 1 | MainExe |
| ~ changed | RegVersion | 2 | SOFTWARE\Contoso\DemoApp | Version | **1.0.0** -> **1.1.0** | MainExe |

</details>

<details>
<summary><b>Upgrade - +2 / -2 / ~0</b></summary>

Match key: `UpgradeCode, VersionMin, VersionMax, Language, Attributes`

| Status | UpgradeCode | VersionMin | VersionMax | Language | Attributes | Remove | ActionProperty |
| --- | --- | --- | --- | --- | --- | --- | --- |
| - removed | {6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111} | (null) | 1.0.0 | (null) | 256 | (null) | WIX_UPGRADE_DETECTED |
| - removed | {6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111} | 1.0.0 | (null) | (null) | 2 | (null) | WIX_DOWNGRADE_DETECTED |
| + added | {6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111} | (null) | 1.1.0 | (null) | 256 | (null) | WIX_UPGRADE_DETECTED |
| + added | {6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111} | 1.1.0 | (null) | (null) | 2 | (null) | WIX_DOWNGRADE_DETECTED |

</details>

