on run arguments
    set trackID to item 1 of arguments
    set outputFile to POSIX file (item 2 of arguments)
    tell application id "com.apple.Music"
        set sourceTrack to first track of library playlist 1 whose persistent ID is trackID
        set coverData to raw data of artwork 1 of sourceTrack
    end tell

    set handle to open for access outputFile with write permission
    try
        write coverData to handle
        close access handle
    on error messageText number errorCode
        close access handle
        error messageText number errorCode
    end try
end run
