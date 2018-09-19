#!/bin/bash

### Functions ###

### scriptHelp -- display usage information for this script
function scriptHelp {
    echo "In the future, I will be something helpful!"
}

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"


### Process script parameters

# if no parameters provided, then show the help page and exit with error
if [ -z $1 ]; then
    # show script help page
    scriptHelp 1
fi

# use GetOpts to process parameters
while getopts 'l:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG}"
            ;;
    esac
done



# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
