## Handling arguments

Param (
    [Parameter(Position=0)][string]$Target,
    [string]$Destination,
    [switch]$CleanConfig,
    [switch]$Quiet
)

# Linkit.ps1: Move a folder to a predefined location and create a symbolic link to it (to move folders to a different drive to save space)
Add-Type -AssemblyName PresentationFramework # for the MessageBox
<#
.SYNOPSIS
Move a folder somewhere else and create a link to there

.DESCRIPTION
A folder gets passed in e.g. from a context menu. The script reads from a config file that specifies where to move the folder, moves it there, and creates a link to it in the original parent directory.

.PARAMETER folder
The folder to move

.EXAMPLE
linkit.ps1 "C:\Users\me\Downloads\myfolder"
Moves the folder "myfolder" to a predefined location and creates a link to it in the original parent directory.

.NOTES
EXIT CODES:
0: Success
1: No folder specified
2: Folder does not exist or is not a folder
3: Folder already exists in target location
4: Could not create link
5: Could not move folder
6: User cancelled operation: Folder destination selection
7: User cancelled operation: No config file created
8: Config file is malformed or doesn't exist
#>

## Functions: Create dialog boxes for errors and successes
Function Get-error ($i) {
    if ($false -eq $Quiet) {
        Write-Output "ERR: $i"
        [System.Windows.MessageBox]::Show("Error: $i","Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
Function fatal ($i) {
    if ($false -eq $Quiet) {
        Write-Output "FATAL: $i"
        [System.Windows.MessageBox]::Show("Fatal Error! $i","Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}
Function success ($folder,$dest) {
    if ($false -eq $Quiet) {
        Write-Output "INFO: Moved input folder $folder to $dest"
        [System.Windows.MessageBox]::Show("Success: Moved input folder $folder to $dest", "Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}
# I'm too lazy to call the function with its long name, so I create a shortcut
Function wo ($i) {
    if ($false -eq $Quiet) {
        Write-Output $i
    }
}
## Read config file
function Get-ConfigFile {
    # Check if config file exists
    if (Test-Path -Path %appdata%\linkit\config.cfg) {
        # Read config file
        $config = Get-Content -Path %appdata%\linkit\config.cfg

        # Check if config file is empty
        if ($null -eq $config) {

            # Prompt for new config file
            Write-Output "WARN: No config file found. Prompting for next steps..."
            $Private:result = [System.Windows.MessageBox]::Show("No config file found. Create one now?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
            
            if ($result) {
                Write-Output "INFO: User chose to create a new config file"

                # Create config file
                wo "INFO: Creating config directory..."
                New-Item -ItemType Directory -Path %appdata%\linkit -Force

                wo "INFO: Creating config file..."
                $config = New-Item -ItemType File -Path %appdata%\linkit\config.cfg -Force

                # Prompt for destination
                try {
                    wo "INFO: Prompting for destination..."
                    $dest = [System.Windows.Forms.FolderBrowserDialog]::new()
                    $dest.Description = "Select the destination folder"
                    $dest.ShowDialog()
                    $dest = $dest.SelectedPath
                } catch {
                    fatal "User aborted or an error occured!"
                    exit 6 # just exit the script. Don't want to break anything more
                }
                # Write destination to config file
                wo "INFO: Writing destination to config file..."
                $dest | Out-File -FilePath %appdata%\linkit\config.cfg

                # Prompt for confirmation
                $Private:result = [System.Windows.MessageBox]::Show("Config file created. Move folder now?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
                
            } else {
                # Exit
                Get-error "User chose not to create a new config file"
                exit 7
            }
        }
        # Check if config file has only one line
        if ($config.count -ne 1) {
            Get-error "Config file has more than one line"
            exit 8
        }
        # Check if config file has a valid path
        if (Test-Path -Path $config) {
            $dest = $config
        } else {
            Get-error "Config file has an invalid path"
            exit 8
        }
    } else {
        Get-error "Config file does not exist"
        exit 8
    }
}
## Move folder
function Move-Folder ($folder) {

    # GitHub Copilot spaghetti incoming
    # Check if folder exists
    if (Test-Path -Path $folder) {
        # Check if folder is a directory
        if (Test-Path -Path $folder -PathType Container) {
            # Check if destination exists
            if (Test-Path -Path $dest) {
                # Check if destination is a directory
                if (Test-Path -Path $dest -PathType Container) {
                    # Check if destination is empty
                    if (Get-ChildItem -Path $dest -Recurse -Force -ErrorAction SilentlyContinue) { # Destination is not empty
                        # Prompt for confirmation
                        $Private:result = [System.Windows.MessageBox]::Show("Destination is not empty. Move folder anyway?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
                        if ($result) { # User chose to move folder anyway
                            # Move folder
                            try {
                                start-process powershell.exe -argument "-nologo -noprofile -executionpolicy bypass -command Move-Item -Path $folder -Destination $dest -Force"
                                success $folder $dest
                            } catch {
                                fatal "An error occured while moving the folder: $_"
                                exit 5
                            } # END try to move folder
                        } else { # User chose not to move folder
                            # Prompt for a workaround
                            $Private:parent = [System.Windows.MessageBox]::Show("Move folder to a symbolic parent directory?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
                            if ($parent) { # User chose to move folder to a symbolic parent directory
                                # Get parent directory
                                $parent = Split-Path -Path $folder -Parent

                                # Create a folder with the same name as the parent directory, but in the destination root
                                New-Item -ItemType Directory -Path $dest -Name $parent -Force

                                # Join the paths for the new destination
                                $dest = Join-Path -Path $dest -ChildPath $parent

                                # Move folder
                                try {
                                    start-process powershell.exe -argument '-nologo -noprofile -executionpolicy bypass -command Move-Item -Path $folder -Destination $dest -Force'
                                    success $folder $dest
                                } catch {
                                    fatal "An error occured while moving the folder: $_"
                                    exit 5
                                } # END try to move folder

                            } else { # User chose not to move folder to a symbolic parent directory
                                # Exit
                                Get-error "User chose not to move folder to a symbolic parent directory"
                                exit 3
                            } # END if user chose to move folder to a symbolic parent directory
                        } #END prompt for confirmation due to non-empty destination
                    } else { # Folder can be moved safely (destination is empty)
                        # Move folder
                        try {
                            start-process powershell.exe -argument '-nologo -noprofile -executionpolicy bypass -command Move-Item -Path $folder -Destination $dest -Force'
                            success $folder $dest
                        } catch {
                            fatal "An error occured while moving the folder: $_"
                            exit 5
                        } # END try to move folder
                    } # END check if destination is empty and move
                } else { # Destination is not a directory
                    Get-error "Destination is not a directory"
                    exit 2
                } # END check if destination is a directory
            } else { # Destination does not exist
                Get-error "Destination does not exist"
                exit 2
            } # END check if destination exists
        } else { # Input folder is not a directory
            Get-error "Input folder is not a directory"
            exit 2
        } # END check if input folder is a directory
    } else { # Input folder does not exist
        Get-error "Input folder does not exist"
        exit 2
    } # END check if input folder exists
    
}

## Create link
function New-Link ($folder,$dest) { # $folder is the folder to be linked, $dest is the destination of the link (the folder's original parent directory)
    # Check if folder exists
    if (Test-Path -Path $folder) {
        # Check if folder is a directory
        if (Test-Path -Path $folder -PathType Container) {
            # Check if destination exists
            if (Test-Path -Path $dest) {
                # Check if destination is a directory
                if (Test-Path -Path $dest -PathType Container) {
                    # Check if destination is empty
                    if (Get-ChildItem -Path $dest -Recurse -Force -ErrorAction SilentlyContinue) { # Destination is not empty
                        # Prompt for confirmation
                        $Private:result = [System.Windows.MessageBox]::Show("Destination is not empty. Create link anyway?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
                        if ($result) { # User chose to create link anyway
                            # Create link
                            try {
                                New-Item -ItemType SymbolicLink -Path $dest -Name $folder -Value $folder -Force
                                success $folder $dest
                            } catch {
                                fatal "An error occured while creating the link: $_"
                                exit 4
                            } # END try to create link
                        } else { # User chose not to create link
                            # Exit
                            fatal "User chose not to create the link"
                            exit 4
                        } #END prompt for confirmation due to non-empty destination
                    } else { # Link can be created safely (destination is empty)
                        # Create link
                        try {
                            New-Item -ItemType SymbolicLink -Path $dest -Name $folder -Value $folder -Force
                            success $folder $dest
                        } catch {
                            fatal "An error occured while creating the link: $_"
                            exit 4
                        } # END try to create link
                    } # END check if destination is empty and create link
                } else { # Destination is not a directory
                    Get-error "Destination is not a directory"
                    exit 2
                } # END check if destination is a directory
            } else { # Destination does not exist
                Get-error "Destination does not exist"
                exit 2
            } # END check if destination exists
        } else { # Input folder is not a directory
            Get-error "Input folder is not a directory"
            exit 2
        } # END check if input folder is a directory
    } else { # Input folder does not exist
        Get-error "Input folder does not exist"
        exit 2
    } # END check if input folder exists
}

