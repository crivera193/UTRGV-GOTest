param([string]$Serial = 'emulator-5554')
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\sephi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
# Use the same intent identity as the launcher, so Back/Home/Recents share a task.
& $adb -s $Serial shell am start -W --display 0 -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -f 0x10200000 -n com.example.campus_app/.MainActivity
if ($LASTEXITCODE -ne 0) { throw 'UTRGV-GO preview launch failed.' }
