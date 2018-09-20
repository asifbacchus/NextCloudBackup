#!/bin/bash


### Text formatting presets
normal="\e[0m"
bold="\e[1m"
default="\e[39m"
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
magenta="\e[35m"
cyan="\e[36m"
stamp="[`date +%Y-%m-%d` `date +%H:%M:%S`]"


### Functions ###

### scriptHelp -- display usage information for this script
function scriptHelp {
    echo "In the future, I will be something helpful!"
    # exit with code 1 -- there is no use logging this
    exit 1
}

### quit -- exit the script after logging any errors, warnings, etc. and 
### cleaning up as necessary
function quit {
    if [ -z "$1" ]; then
        # exit cleanly
        echo -e "${bold}${green}${stamp} -- [SUCCESS] Script completed" \
            "--$normal" >> "$logFile"
        exit 0
    else
        # log error code and exit with said code
        echo -e "${bold}${red}${stamp} -- [ERROR] Script exited with code $1" \
            " --$normal" >> "$logFile"
        echo -e "${red}${errorExplain[$1]}$normal" >> "$logFile"
        exit "$1"
    fi
}

function checkExist {
    if [ "$1" = "ff" ]; then
        # find file
        if [ -e "$2" ]; then
            # found
            echo -e "${normal}${stamp} File found:" \
                "${bold}${yellow}${2}${normal}" >> "$logFileVerbose"
            return 0
        else
            # not found
            echo -e "${red}${stamp} File NOT found:"\
                "${bold}${yellow}${2}${normal}" >> "$logFileVerbose"
            return 1
        fi
    elif [ "$1" = "fd" ]; then
        # find directory
        if [ -d "$2" ]; then
            # found
            echo -e "${normal}${stamp} Dir found:" \
                "${bold}${yellow}${2}${normal}" >> "$logFileVerbose"
            return 0
        else
            # not found
            echo -e "${red}${stamp} Dir NOT found:" \
                "${bold}${yellow}${2}${normal}" >> "$logFileVerbose"
            return 1
        fi
    fi
}

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"

# set script parameters to null and initialize array variables
unset PARAMS
unset logLevel
unset logFileNormal
unset logFileVerbose
unset borgCreateParams
unset borgPruneParams
unset sqlDumpDir
unset 503Location
unset webroot
errorExplain=()
exitWarn=()
warningExplain=()


### Error codes
errorExplain[2]="This script MUST be run as ROOT."


### Warning codes & messages
warningExplain[5031]="No path to a 503 error page file was specified (-5 parameter missing)"
warningExplain[5032]="The specified 503 error page could not be found"
warningExplain[5033]="No webroot path was specified (-w parameter missing)"
warningExplain[5034]="The specified webroot could not be found"
warningExplain[5035]="Error copying 503 error page to webroot"
warn503="${bold}${yellow}Web users will NOT be informed the server is down!${normal}"

### Process script parameters

# if no parameters provided, then show the help page and exit with error
if [ -z $1 ]; then
    # show script help page
    scriptHelp
fi

# use GetOpts to process parameters
while getopts ':l:nv5:w:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG}"
            ;;
        n)
            # standard logging (script errors, Borg summary)
            logLevel="normal"
            ;;
        v)
            # verbose logging (script errors, Borg details)
            logLevel="verbose"
            ;;
        5)
            # 503 error page location
            503Location="${OPTARG}"
            ;;
        w)
            # path to webroot for NextCloud installation
            webroot="${OPTARG}"
            ;;
        ?)
            # unrecognized parameters trigger scriptHelp
            scriptHelp
            ;;
    esac
done


### Verify script running as root, otherwise exit
if [ $(id -u) -ne 0 ]; then
    quit 2
fi


### Set logging verbosity based on invocation parameters
if [ "$logLevel" = "normal" ]; then
    borgCreateParams='--stats'
    borgPruneParams="--list"
    logFileVerbose="/dev/null"
    logFileNormal="$logFile"
elif [ "$logLevel" = "verbose" ]; then
    borgCreateParams='--list --stats'
    borgPruneParams='--list'
    logFileVerbose="$logFile"
    logFileNormal="/dev/null"
fi


### Log start of script operations
echo -e "${bold}${stamp}-- Start $scriptName execution ---" >> "$logFile"


### Export logFile variable for use by Borg
export logFile="$logFile"


### Create sqlDump temporary directory and sqlDumpFile name
sqlDumpDir=$( mktemp -d )
echo -e "${cyan}${stamp} Created temp dir for SQLdump: $sqlDumpDir" \
    >> "$logFileVerbose"
sqlDumpFile="backup-`date +%Y%m%d_%H%M%S`.sql"
echo -e "${normal}${stamp} mySQL dump file will be stored at:" \
    "${bold}${yellow}${sqlDumpDir}/${sqlDumpFile}${normal}" \
    | tee -a "$logFileNormal" "$logFileVerbose" > /dev/null


### 503 error page

# Verify 503 existance
if [ -z "$503Location" ]; then
    # no 503 file has been provided
    echo -e "${bold}${yellow}${stamp} -- [WARNING] ${warningExplain[5031]}" \
        "--${normal}" >> "$logFile"
    exitWarn+=('5031')
else
    checkExist ff "$503Location"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # 503 file specified could not be found
        echo -e "${bold}${yellow}${stamp} -- [WARNING]" \
            "${warningExplain[5032]} --${normal}" >> "$logFile"
        exitWarn+=('5032')
    else
        # 503 file found
        echo -e "${bold}${stamp}Found: ${yellow}${503Location}${normal}" \
            >> "$logFileVerbose"
        
        # verify webroot exists
        if [ -z "$webroot" ]; then
            # no webroot path provided
            echo -e "${bold}${yellow}${stamp} -- [WARNING]" \
                "${warningExplain[5033]} --${normal}" >> "$logFile"
            exitWarn+=('5033')
        else
            # verify provided webroot path exists
            checkExist fd "$webroot"
            checkResult="$?"
            if [ "$checkResult" = "1" ]; then
                # webroot directory specified could not be found
                echo -e "${bold}${yellow}${stamp} -- [WARNING]" \
                    "${warningExplain[5034]} --${normal}" >> "$logFile"
                exitWarn+=('5034')
            else
                # webroot exists and 503 exists, copy 503 to webroot
                echo -e "${bold}${cyan}${stamp} Copying 503 error page to" \
                    "webroot...${normal}" >> "$logFileVerbose"
                cp "${503Location}" "$webroot/" >> "$logFileVerbose" 2>&1
                copyResult="$?"
                # verify copy was successful
                    if [ "$copyResult" = "1" ]; then
                        echo -e "${bold}${yellow}${stamp} -- [WARNING]" \
                            "${warningExplain[5035]} --${normal}" >> "$logFile"
                        exitWarn+=('5035')
                    else
                        # copy was successful
                        echo -e "${bold}${cyan}${stamp} ...done" \
                        >> "$logFileVerbose"
                    fi
            fi
        fi
    fi
fi



# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
