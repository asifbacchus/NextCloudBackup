#!/bin/bash


### Text formatting presets
normal="\e[0m"
bold="\e[1m"
default="\e[39m"
err="\e[1;31m"
warn="\e[1;93m"
ok="\e[32m"
lit="\e[93m"
op="\e[39m"
info="\e[96m"
stamp="[`date +%Y-%m-%d` `date +%H:%M:%S`]"


### Functions ###

### scriptHelp -- display usage information for this script
function scriptHelp {
    echo "In the future, I will be something helpful!"
    # exit with code 1 -- there is no use logging this
    exit 1
}

### quit -- exit the script after logging any errors, warnings, etc.
function quit {
    # list generated warnings, if any
    if [ ${#exitWarn[@]} -gt 0 ]; then
        echo -e "${warn}${scriptName} generated the following warnings:" \
            "${normal}" >> "$logFile"
        for warnCode in "${exitWarn[@]}"; do
            echo -e "${warn}-- [WARNING] ${warningExplain[$warnCode]}" \
                "(code: ${warnCode}) --${normal}" >> "$logFile"
        done
    fi
    if [ -z "$1" ]; then
        # exit cleanly
        echo -e "\e[1;35m${stamp} -- ${scriptName} completed" \
            "--${normal}" >> "$logFile"
        exit 0
    else
        # log error code and exit with said code
        echo -e "${err}${stamp} -- [ERROR] ${errorExplain[$1]}" \
            "(code: $1) --$normal" >> "$logFile"
        exit "$1"
    fi
}

function checkExist {
    if [ "$1" = "ff" ]; then
        # find file
        if [ -e "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    elif [ "$1" = "fd" ]; then
        # find directory
        if [ -d "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    fi
}

### ncMaint - perform NextCloud maintenance mode entry and exit
function ncMaint {
    if [ "$1" = "on" ]; then
        echo -e "${info}${stamp} -- [INFO] Putting NextCloud in maintenance" \
            "mode --${normal}" >> "$logFile"
        su -c "php ${ncRoot}/occ maintenance:mode --on" - ${webUser} \
            >> "$logFile" 2>&1
        maintResult="$?"
        return "$maintResult"
    elif [ "$1" = "off" ]; then
        echo -e "${info}${stamp} -- [INFO] Exiting NextCloud maintenance" \
            "mode --${normal}" >> "$logFile"
        su -c "php ${ncRoot}/occ maintenance:mode --off" - ${webUser} \
            >> "$logFile" 2>&1
        maintResult="$?"
        return "$maintResult"
    fi
}

### cleanup - cleanup files and directories created by this script
function cleanup {
    ## remove SQL dump file and directory
    rm -rf "$sqlDumpDir" >> "$logFile" 2>&1
    # verify directory is gone
    checkExist fd "$sqlDumpDir"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        # directory still exists
        exitWarn+=('111')
    else
        # directory removed
        echo -e "${op}${stamp} Removed SQL temp directory${normal}" \
            >> "$logFile"
    fi

    ## remove 503 error page
    # check if webroot was specified, if not, then nothing was copied so we can
    # skip this whole section
    if [ -n "$webroot" ]; then
        # proceed with cleanup
        rm -f "$webroot/$err503File" >> "$logFile" 2>&1
        # verify file is actually gone
        checkExist ff "$webroot/$err503File"
        checkResult="$?"
        if [ "$checkResult" = "0" ]; then
            # file still exists
            exitWarn+=('5030')
        else
            # file removed
            echo -e "${info}${stamp} -- [INFO] 503 page removed from webroot" \
                "--${normal}" >> "$logFile"
        fi
    else
        echo -e "${op}${stamp} No webroot specified so no 503 file to remove." \
            >> "$logFile"
    fi
}

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"

# set default 503 error page name and location in scriptPath
err503Path="$scriptPath/503.html"
err503File="${err503Path##*/}"

# set borg parameters to 'normal' verbosity
borgCreateParams='--stats'
borgPruneParams='--list'


### Set script parameters to null and initialize array variables
unset PARAMS
unset sqlDumpDir
unset webroot
unset ncRoot
errorExplain=()
exitWarn=()
warningExplain=()


### Error codes
errorExplain[100]="Could not put NextCloud into Maintenance mode."

### Warning codes & messages
warningExplain[111]="Could not remove SQL dump file and directory.  Please remove manually."
warningExplain[5030]="Could not remove 503 error page. This MUST be removed manually before NGINX will serve webclients!"
warningExplain[5031]="No webroot path was specified (-w parameter missing)."
warningExplain[5032]="The specified webroot (-w parameter) could not be found."
warningExplain[5033]="No 503 error page could be found. If not using the default located in the script directory, then check your -5 parameter."
warningExplain[5035]="Error copying 503 error page to webroot"
warn503="Web users will NOT be informed the server is down!"

### Process script parameters

# If parameters are provided but don't start with '-' then show the help page
# and exit with an error
if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
    # show script help page
    scriptHelp
fi

# use GetOpts to process parameters
while getopts ':l:n:v5:w:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG}"
            ;;
        n)
            # NextCloud webroot
            ncRoot="${OPTARG}"
            ;;
        v)
            # verbose output from Borg
            borgCreateParams='--list --stats'
            borgPruneParams='--list'
            ;;
        5)
            # Full path to 503 error page
            err503Path="${OPTARG%/}"
            ;;
        w)
            # path to webserver webroot to copy 503 error page
            webroot="${OPTARG%/}"
            ;;
        ?)
            # unrecognized parameters trigger scriptHelp
            scriptHelp
            ;;
    esac
done


### Verify script pre-requisties
# If not running as root, display error on console and exit
if [ $(id -u) -ne 0 ]; then
    echo -e "${err}This script MUST be run as ROOT. Exiting.${normal}"
    exit 2
#elif [ -z "$ncRoot" ]; then
#    echo -e "\n${err}The NextCloud webroot must be specified (-n parameter)" \
#        "${normal}\n"
#    exit 1
fi


### Log start of script operations
echo -e "\e[1;35m${stamp}-- Start $scriptName execution ---${normal}" \
    >> "$logFile"


### Export logFile variable for use by Borg
export logFile="$logFile"


### Create sqlDump temporary directory and sqlDumpFile name
sqlDumpDir=$( mktemp -d )
sqlDumpFile="backup-`date +%Y%m%d_%H%M%S`.sql"
echo -e "${info}${stamp} -- [INFO] mySQL dump file will be stored" \
    "at: ${lit}${sqlDumpDir}/${sqlDumpFile}${normal}" >> "$logFile"


### 503 error page: If you dont' plan on using the auto-copied 503 then comment
### this entire section starting with '--- Begin 503 section ---' until
### '--- End 503 section ---' to suppress generated warnings

### --- Begin 503 section ---

## Check if webroot has been specified, if not, skip this entire section since there is nowhere to copy the 503 file.
if [ -z "$webroot" ]; then
    # no webroot path provided
    echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
        >> "$logFile"
    exitWarn+=('5031')
else
    # verify webroot actually exists
    checkExist fd "$webroot"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # webroot directory specified could not be found
        echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
            >> "$logFile"
        exitWarn+=('5032')
    else
        # webroot exists
        echo -e "${op}${stamp} Using webroot: ${lit}${webroot}${normal}" \
            >> "$logFile"
        # Verify 503 file existance at given path
        checkExist ff "$err503Path"
        checkResult="$?"
        if [ "$checkResult" = "1" ]; then
            # 503 file could not be found
            echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
                >> "$logFile"
            exitWarn+=('5033')
        else
            # 503 file exists and webroot is valid. Let's copy it!
            echo -e "${op}${stamp} ${err503File} found.${normal}" >> "$logFile"
            echo -e "${op}${stamp} Copying 503 error page to webroot..." \
                "${normal}" >> "$logFile"
            cp "${err503Path}" "$webroot/" >> "$logFile" 2>&1
            copyResult="$?"
            # verify copy was successful
                if [ "$copyResult" = "1" ]; then
                    # copy was unsuccessful
                    echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
                        >> "$logFile"
                    exitWarn+=('5035')
                else
                # copy was successful
                echo -e "${info}${stamp} -- [INFO] 503 error page" \
                    "successfully copied to webroot --${normal}" >> "$logFile"
                fi
        fi
    fi
fi

### --- End 503 section ---


### Put NextCloud in maintenance mode
#ncMaint on
# check if successful
#if [ "$maintResult" = "0" ]; then
#    echo -e "${bold}${cyan}${stamp}...done${normal}" >> "$logFile"
#else
#    cleanup 503
#    quit 100
#fi

### Exit script
cleanup
quit

# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
