## Handling arguments
# TODO: loop in the message box api. Still struggling w/ that.
# ISSUES: literally nothing works. I think my computer is haunted.
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
9: Copied checksum does not match original checksum
10: Permissions error
#>

## Functions: Create dialog boxes for errors and successes
Function Get-error ($i) {
    if ($false -eq $Quiet) {
        wo "ERR: $i"
        [System.Windows.MessageBox]::Show("Error: $i","Linkit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
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
    if ($false -eq $Quiet) {
        Write-Output $i
    }
    Out-File -FilePath %appdata%/linkit/latest.log -Append
    Out-File -FilePath $LogDated -Append
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
            wo "WARN: No config file found. Prompting for next steps..."
            $Private:result = [System.Windows.MessageBox]::Show("No config file found. Create one now?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
            
            if ($result) {
                wo "INFO: User chose to create a new config file"

                # Create config file

                if (Test-Path -Path %appdata%\linkit) {
                    wo "INFO: Config directory already exists"
                } else {
                    wo "INFO: Creating config directory"
                    New-Item -ItemType Directory -Path %appdata%\linkit
                }

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
function Copy-Folder ($folder,$dest) {

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
                                    start-process powershell.exe -argument '-nologo -noprofile -executionpolicy bypass -command Copy-Item -Path $folder -Destination $dest -Force'
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
                            start-process powershell.exe -argument '-nologo -noprofile -executionpolicy bypass -command Copy-Item -Path $folder -Destination $dest -Force'
                            success $folder $dest
                        } catch {
                            fatal "An error occured while copying the folder: $_"
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

function CompareSum ($folder,$dest) {
    # Generate source checksum
    wo "DBG: Generating source checksum (this might take a while)..."
    wo "DBG: Generating and combining all file hashes..."
    $HashStringSrc = (Get-ChildItem $folder -Recurse | Get-FileHash -Algorithm SHA512).Hash | Out-String
    wo "DBG: Generating checksum of that list of checksums..."
    $HashSrc = Get-FileHash -InputStream ([IO.MemoryStream]::new([char[]]$HashStringSrc))
    wo "DBG: Source checksum generated: $HashSrc"
    # Generate destination checksum
    wo "DBG: Generating destination checksum (this might take a while)..."
    wo "DBG: Generating and combining all file hashes..."
    $HashStringDest = (Get-ChildItem $dest -Recurse | Get-FileHash -Algorithm SHA512).Hash | Out-String
    wo "DBG: Generating checksum of that list of checksums..."
    $HashDest = Get-FileHash -InputStream ([IO.MemoryStream]::new([char[]]$HashStringDest))
    wo "DBG: Destination checksum generated: $HashDest"

    # Compare checksums
    $SumResult = if ($HashSrc.Hash -eq $HashDest.Hash) {
        wo "DBG: Checksums match"
        return $true
    } else {
        wo "ERR: Checksums do not match"
        return $false
    }

    if ($SumResult) {
        wo "DBG: Checksums match; files are valid"
    } else {
        get-error "Checksums do not match; files are invalid"
        # Ask the user whether to delete the copied folder and try copying again, or to just delete the files and exit
        $Private:result = [System.Windows.MessageBox]::Show("Checksums do not match. Delete copied files and try again?","Linkit", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq "Yes"
        if ($Private:result) {
            wo "DBG: User chose to delete copied files and try again"
            Remove-Item $dest -Recurse -Force
            wo "DBG: Deleted copied files"
            return $true
        } else {
            wo "DBG: User chose to delete copied files and exit"
            Remove-Item $dest -Recurse -Force
            wo "DBG: Deleted copied files"
            return $false
        }
    }
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

## Main - Logging
if (Test-Path %appdata%/linkit/latest.log) { # Check if latest log file exists
    Remove-Item %appdata%/linkit/latest.log -Force
    wo "DBG: Removed latest.log; new file initialized (this should be the first line in the file)"
}

# Configure the log file target
$LogDatedTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
wo "DBG: Set dated log time to $LogDatedTime"
$LogDated = %appdata%/linkit/log-\($LogDatedTime).log
wo "DBG: Set dated log file to $LogDated"

## Main - Argument parsing

# -CleanConfig
if ($CleanConfig) {
    # Clean config
    Remove-Item -Path %appdata%/Linkit/config.cfg -Force
    wo "DBG: Cleaned config at user request"
    exit 0
}
if ($null -eq $Target -and $false -eq $CleanConfig) { # No arguments were passed
    # No target specified
    fatal "No arguments!"
    exit 1
}

# Start the actual thing
try { # Config file loading
    Get-ConfigFile # this is such a loaded line lmfao
    wo "DBG: Loaded config file!"
wo "DBG: Destination is $Config"
} catch {
    fatal "VERY BAD: Uncaught error occured while getting config file (this shouldn't happen): $_" # if this happens we have bigger problems
}

# and now, the part you've all been waiting for
function copyprocess {
    if ($null -ne $Destination) {
        wo "DBG: Destination specified: $Destination"
        try {
            $FinalDestination = $Destination
            Move-Folder $Target $Destination
        } catch {
            fatal "VERY BAD: Uncaught error occured while copying folder: $_"
        }
    } else {
        wo "DBG: Destination not specified; using config"
        try {
            $FinalDestination = $Config
            Move-Folder $Target $Config
        } catch {
            fatal "VERY BAD: Uncaught error occured while copying folder: $_"
        }
    }
    $summing = CompareSum $Target $FinalDestination
    if ($summing) {
        wo "DBG: Checksums match; files are valid"
        try {
            Remove-Item -WhatIf $Target -Recurse
        } catch {
            fatal "Your files are valid, but an error occured while deleting the original folder: $_ \n This might be caused by a permissions error. The files might be important, so make sure you know what you're doing before deleting them! \n If you're sure you want to delete them, you can do so by locating the directory this script is located in, opening a new terminal session, and running the script as an administrator. The command to do this is copied to your clipboard. \n THE DEVELOPERS OF THIS SCRIPT, MICROSOFT WINDOWS, AND EVERY OTHER DEVELOPER ARE NOT LIABLE BOR LOSS OF LIFE, PROPERTY, OR DATA. YOU ARE USING THIS SCRIPT AT YOUR OWN RISK. \n There also might be a process using a file in the directory, so quit all relevant applications. \n\n YOUR FILES HAVE NOT BEEN TOUCHED."
            $ManualCommand = "powershell -verb runas -ExecutionPolicy Bypass -File $PSScriptRoot\linkit.ps1 -Target $Target -Destination $Destination"
            Set-Clipboard $ManualCommand
            exit
        }
        New-Link $Target $FinalDestination
    } else {
        # At this point, the files at the destination are invalid and should have been deleted. We can safely exit.
        success "Copied files are invalid and are deleted. Your original files are still intact."
        exit 9
    }
}
