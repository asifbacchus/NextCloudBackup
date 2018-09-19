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
    # exit with code 98 -- there is no use logging this
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

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"

# set script parameters to null and initialize array variables
unset PARAMS
errorExplain=()


### Error codes
errorExplain[2]="This script MUST be run as ROOT."


### Process script parameters

# if no parameters provided, then show the help page and exit with error
if [ -z $1 ]; then
    # show script help page
    scriptHelp
fi

# use GetOpts to process parameters
while getopts ':l:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG}"
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


### Log start of script operations
echo -e "${bold}${stamp}-- Start $scriptName execution ---" >> "$logFile"




# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
