Add-Type -AssemblyName PresentationFramework
Function Get-error ($i) {
    if ($false -eq $Quiet) {
        wo "ERR: $i"
        Add-Type -AssemblyName PresentationFramework;[System.Windows.MessageBox]::Show("Error: $i","Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
Function fatal ($i) {
    if ($false -eq $Quiet) {
        wo "FATAL: $i"
        [System.Windows.MessageBox]::Show("Fatal Error! $i","Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
Function success ($folder,$dest) {
    if ($false -eq $Quiet) {
        wo "INFO: Moved input folder $folder to $dest"
        [System.Windows.MessageBox]::Show("Success: Moved input folder $folder to $dest", "Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}
# I'm too lazy to call the function with its long name, so I create a shortcut
Function wo ($i) {
    Write-Output $i
}
Get-error $args
fatal $args
success $args