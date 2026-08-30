!macro customInstallMode
  ; WeiBei is deliberately per-user. This prevents a silent/elevated repair
  ; from drifting into Program Files or writing an HKLM uninstall record.
  StrCpy $isForceCurrentInstall "1"
  StrCpy $isForceMachineInstall "0"
!macroend
