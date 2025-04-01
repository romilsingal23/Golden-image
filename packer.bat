dir c:\temp\Files
#:::::::::::::::::::::Disable IPV6::::::::::::::::
# powershell -ExecutionPolicy Bypass -file c:\temp\Files\disable_ipv6.ps1
#:::::::::::::::::::Change CD to Z:::::::::::::::::::
# $cdDrive = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = 'E:'"
  #  Set-CimInstance -InputObject $cdDrive -Property @{DriveLetter = 'Z:'}

#:::::::::::::::::::::::encript SMB3
# powershell -ExecutionPolicy Bypass  Set-SmbServerConfiguration -EncryptData $true -force
#::::::::::::::::::::::::::::::allow Ping::::::::::::::::::
netsh advfirewall firewall add rule name="ICMP Allow incoming V4 echo request" protocol=icmpv4:8,any dir=in action=allow

md "c:\users\default\appdata\Local\Microsoft\Windows\Themes"
copy c:\temp\Files\QuestTheme.theme "c:\users\default\appdata\Local\Microsoft\Windows\Themes"
takeown /f c:\windows\WEB\wallpaper\Windows\img0.jpg
takeown /f c:\Windows\Web\4K\Wallpaper\Windows\*.*
icacls c:\windows\WEB\wallpaper\Windows\img0.jpg /Grant Everyone:(F)
icacls c:\Windows\Web\4K\Wallpaper\Windows\*.* /Grant Everyone:(F)
del c:\windows\WEB\wallpaper\Windows\img0.jpg
del /q c:\Windows\Web\4K\Wallpaper\Windows\*.*
copy c:\temp\Files\qss.jpg c:\windows\WEB\wallpaper\Windows\img0.jpg
copy c:\temp\Files\4k\*.* c:\Windows\Web\4K\Wallpaper\Windows
copy c:\temp\Files\QuestDeepSeaClassic.jpg c:\Windows\web\Screen\
regedit /s /i c:\temp\Files\lockscreenimage.reg
regedit /s /i c:\temp\Files\theme.reg
copy c:\temp\Files\qss.bmp %WINDIR%\SYSTEM32
copy c:\temp\Files\qss.jpg %WINDIR%\SYSTEM32
copy c:\temp\Files\QuestDeepSeaClassic.jpg %WINDIR%\SYSTEM32
copy c:\temp\Files\QuestTheme.theme %WINDIR%\SYSTEM32
copy c:\temp\Files\oeminfo.ini %WINDIR%\SYSTEM32
copy c:\temp\Files\oemlogo.bmp %WINDIR%\SYSTEM32
copy c:\temp\files\logoff.* c:\Users\Default\desktop



regedit /s /i c:\temp\Files\vulrem\CVE-2018-3639.reg
regedit /s /i c:\temp\Files\vulrem\Disable_Last_UserName.reg
regedit /s /i c:\temp\Files\vulrem\Disable_AutoPlay.reg
regedit /s /i c:\temp\Files\vulrem\Disable_CachedLogonCreds.reg
regedit /s /i c:\temp\Files\vulrem\Disable_SSL_TLS_NET_win2022.reg
cscript /b c:\temp\Files\vulrem\Rename_Guest_Acct.vbs /ato
regedit /s /i c:\temp\Files\vulrem\Disable_Weak_Ciphers.reg
regedit /s /i c:\temp\Files\vulrem\Disable_NullSessions.reg
regedit /s /i c:\temp\Files\vulrem\Disable_NtpServer.reg
regedit /s /i c:\temp\Files\vulrem\SMB_Signing_Require.reg
regedit /s /i c:\temp\Files\vulrem\Disable_SMBv1_Client.reg
regedit /s /i c:\temp\Files\vulrem\DisableAutoLogon.reg
regedit /s /i c:\temp\Files\vulrem\WinVerifyTrust.reg
regedit /s /i c:\temp\Files\vulrem\MSORemote.reg

:: Disable Windows print spooler
copy c:\files\Disable-PrintSpooler.ps1 c:\temp\files

:: Disable Windows deffender
powershell -ExecutionPolicy Bypass -file c:\temp\files\local_defender_disable.ps1

:: Disabling unnecessary services

call c:\temp\Files\DisableService.bat

regedit /s /i c:\temp\Files\system_tweaks_2022.reg

rd c:\temp /s /q

