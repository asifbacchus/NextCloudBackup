#!/bin/bash

#######
### Backup NextCloud13 installation to external repo using Borg Backup
### Assuming both NextCloud & Borg setup as outlined in their respecitive
### series at https://mytechiethoughts.com
###
### Events:
### 1. Copy 503 error page to stop NGINX from serving web clients.
###       (this depends on a complementary NGINX configuration)
### 2. Put NextCloud in maintenance mode to prevent logins and changes.
### 3. SQLdump from NextCloud.
### 4. Borg backup all files from xtraLocations.
### 5. Borg backup NextCloud data and files.
### 6. Put NextCloud back into operating mode.
### 7. Delete 503 error page so NGINX can serve web clients again.
###
### Usage: ./borgbackup [verbose:normal(default):quiet]
### Options:
###   verbose - All logging turned on, including a list of each file being
###       backed up/skipped/etc. (This can lead to very large logs)
###   normal - This is the default setting. If nothing is specified, this
###       setting will be used. Errors, warnings & summary of borgbackup will
###       be logged.
###   quiet - Minimal logging. Errors and warnings only and confirmation of
###       of backup success.
#######


### Script variables -- please ensure they are accurate!

# web user on your system (default: www-data)
webUser=www-data

# FULL path to NGINX webroot (default: /usr/share/nginx/html)
webroot=/usr/share/nginx/html

# FULL path to NextCloud root directory
# By default, this is a folder within your webroot. If your setup is different
# then provide the FULL path here. (default: webroot/nextcloud)
ncroot="$webroot/nextcloud"

# NextCloud data directory
# If this is setup according to the blog series at https://mytechiethoughts.com
# then this is '/var/nc_data'.  If not, please change as appropriate for your
# environment. (default: /var/nc_data)
ncdata=/var/nc_data

# name of 503-error page (default: 503-error.html)
# MUST be in the same directory as THIS script
err503FileName=503-backup.html

# desired directory for SQLdump -- will be created if necessary
# (default: /SQLdump)
sqlDumpDir=/SQLdump

# FULL path to SQL details file (explained in blog)
# This is a 4 line file in the EXACT format:
#sqlServerHostName
#sqlDBUsername
#sqlDBPassword
#sqlDBName
#(default: /root/sqlDetails)
sqlDetails=/root/sqlDetails

# Borg BASE directory (default: /var/borgbackup)
borgBaseDir=/var/borgbackup

# FULL path to your remote server SSH private keyfile (no default)
borgRemoteSSHKeyfile=/var/borgbackup/rsync.key

# Borg remote path (default for rsync: borg1)
borgRemotePath=borg1

# Borg 'checkpoint' interval in seconds
# This determines when snapshots are taken so that interrupted backups
# can be restored from that point in time
# (default: 300 seconds = 5 minutes)
borgCheckpoint=300

# FULL path to Borg repo details file (explained in blog)
# This is a 2 line file in the EXACT format:
# repo-name in format user@server.tld:repo
# passphrase
# (default: borgBaseDir/repoDetails.borg)
borgDetails="$borgBaseDir/repoDetails.borg"

# FULL path to the extra source-list file (explained in blog)
# This file lists any extra files and directories that should be included
# in the backup in addition to NextCloud program and data files.
# One source-entry per line.
# No spaces, comments or any other extraneous information, just the files/dirs
#    Directories must end with tailing slash (i.e. directory/name/)
# (default: borgBaseDir/xtraLocations.borg)
borgXtraFiles="$borgBaseDir/xtraLocations.borg"

# FULL path to the exclude source-list (explained in blog)
# This file lists any files and directories that should be excluded from
# the backup.
# MUST conform to borg patterns -- 'borg help patterns' for more information
# (default: borgBaseDir/excludeLocations.borg)
borgExcludeFiles="$borgBaseDir/excludeLocations.borg"

# Pruning options for borg archive (see BorgBackup documentation for details)
# This default example keeps all backups within the last 14 days, 12 weeks
# of end-of-week backups and 6 months of end-of-month backups.
borgPrune='--keep-within=14d --keep-weekly=12 --keep-monthly=6'

# desired name and location of log file for this script (will be created)
# NOTE: This file can get quite large, ensure logrotate is setup!
# (default: /var/log/mailcow_backup.log)
logFile=/var/log/borgbackup.log


### Do NOT edit below this line


## Ensure script is running as root (required) otherwise, exit
if [ $(id -u) -ne 0 ]; then
    echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`] This script MUST" \
        "be run as ROOT."
    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m"
    exit 1
fi


## elevate script -- used during program testing
#if [ $EUID != 0 ]; then
#    sudo "$0" "$@"
#    exit $?
#fi


### Functions:

function quit {
    if [ -z "$1" ]; then
        # exit gracefully
        echo -e "\e[1;32m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
            "--Backup operations completed SUCCESSFULLY--\e[0m" >> $logFile
        exit 0
    elif [ "$2" = "warn" ]; then
        # exit with warning code
        echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
            "--Script exiting with WARNING (code: $1)--\e[0m" >> $logFile
        exit "$1"
    else
        # exit with error code
        echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
            "--Script exiting with ERROR (code: $1)--\e[0m" >> $logFile
        exit "$1"
    fi
}

function checkExist {
    if [ "$1" = "find" ]; then
        if [ -e "$3" ]; then
            echo -e "\e[0m[`date +%Y-%m-%d` `date +%H:%M:%S`] Found:" \
                "\e[0;33m${3}\e[0m" >> $logFileVerbose
            return 0
        elif [ "$2" = "createDir" ]; then
            echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Creating:" \
                "${3}...\e[0m" | tee -a $logFileVerbose $logFileNormal > \
                /dev/null
            mkdir -p "$3" 2>&1 | tee -a $logFileVerbose $logFileNormal \
                > /dev/null
            echo -e "\e[0;36m...done\e[0m" | tee -a $logFileVerbose \
                $logFileNormal > /dev/null
            return 1
        elif [ "$2" = "warn" ]; then
            echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] ---WARNING:" \
                "${3} was not found---\e[0m" | tee -a $logFileVerbose \
                $logFileNormal $logFileQuiet > /dev/null
            exitWarning=101
            return 2
        elif [ "$2" = "error" ]; then
            echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`] ---ERROR:" \
                "${3} was not found---\e[0m" | tee -a $logFileVerbose \
                $logFileNormal $logFileQuiet > /dev/null
            quit 101
        fi
    elif [ "$1" = "verify" ]; then
        if [ -e "$2" ]; then
            echo -e "\e[0m[`date +%Y-%m-%d` `date +%H:%M:%S`] Confirmed:" \
                "\e[0;33m${2}\e[0m" >> $logFileVerbose
            return 0
        else
            echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`] ---ERROR:" \
                "Problem creating ${2}---\e[0m" | tee -a $logFileVerbose \
                $logFileNormal $logFileQuiet > /dev/null
            quit 102
        fi
    fi
}
### End of functions


## Write script execution start in log file
echo -e "\e[1;32m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
    "--Begin backup operations--\e[0m" >> $logFile

## Parse supplied variables and determine additional script vars
scriptPath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
err503FullPath="$scriptPath/$err503FileName"

## Determine verbosity level for logging
if [ "$1" = "verbose" ]; then
    borgCreateParams='--list --stats'
    borgPruneParams='--list'
    logFileVerbose="$logFile"
    unset logFileNormal
    unset logFileQuiet
elif [ "$1" = "normal" ] || [ -z "$1" ]; then
    borgCreateParams='--stats'
    borgPruneParams='--list'
    unset logFileVerbose
    logFileNormal="$logFile"
    unset logFileQuiet
elif [ "$1" = "quiet" ]; then
    unset borgCreateParams
    unset borgPruneParams
    unset logFileVerbose
    unset logFileNormal
    logFileQuiet="$logFile"
else
    quit 2
fi

## Export logfle location for use by external programs
export logFile="$logFile"

## Check for sqlDumpDir and create if necessary
checkExist find createDir $sqlDumpDir
checkResult="$?"
if [ "$checkResult" = "1" ]; then
    # verify creation successful
    checkExist verify $sqlDumpDir
fi

## Create unique filename for sqlDump file
sqlDumpFile="backup_`date +%Y%m%d_%H%M%S`.sql"
echo -e "\e[0m[`date +%Y-%m-%d` `date +%H:%M:%S`] mysql dump file will be" \
    "stored at:" >> $logFile
echo -e "\e[0;33m$sqlDumpDir/$sqlDumpFile\e[0m" | tee -a $logFileVerbose \
    $logFileNormal > /dev/null

## Find 503 error page and copy to NGINX webroot
## File must be in the same location as this script
## IF file is not found, log warning but continue script
checkExist find warn $err503FullPath
checkResult="$?"
if [ "$checkResult" = "2" ]; then
    # file not found, issue warning
    echo -e "\e[1;33m--Warning-- The 503 file should be re-created" \
        "ASAP." >> $logFile
    echo -e "\e[1;33m--Warning-- Web users will NOT be notified the" \
        "server is down.\e[0m" >> $logFile
    echo -e "Script will continue processing..." >> $logFile
else
    # file found, copy it to webroot
    echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Copying 503 error" \
        "page to NGINX webroot..." >> $logFile
    cp $err503FullPath $webroot/ 2>&1 | tee $logFileVerbose $logFileNormal \
        > /dev/null
    # verify copy was successful
    checkExist find warn "$webroot/$err503FileName"
    checkResult="$?"
    if [ "$checkResult" = "2" ]; then
        # file not found, issue warning
        echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
            "There was a problem copying the 503 error page to" \
                "webroot." >> $logFile
        echo -e "\e[1;33m--Warning-- Web users will NOT be notified the" \
            "server is down.\e[0m" >> $logFile
        echo -e "Script will continue processing..." >> $logFile
    fi
fi


if [ -e $err503FullPath ]; then
    echo -e "\e[0m[`date +%Y-%m-%d` `date +%H:%M:%S`] Found 503 error" \
        "page at:" >> $logFile
    echo -e "\e[0;33m$err503FullPath\e[0m" >> $logFile
    # copy 503 to webroot
    echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Copying 503 error" \
        "page to NGINX webroot..." >> $logFile
    cp $err503FullPath $webroot/ &>> $logFile
    # check file actually copied
    if [ -e "$webroot/$err503FileName" ]; then
        echo -e "\e[0;36m...done\e[0m" >> $logFile
    else
        echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
            "There was a problem copying the 503 error page to" \
                "webroot." >> $logFile
        echo -e "\e[1;33m--Warning-- Web users will NOT be notified the" \
            "server is down.\e[0m" >> $logFile
        echo -e "Script will continue processing..." >> $logFile
    fi
else
    echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
        "Could not locate 503 error page at \e[0;33m$err503FullPath" >> $logFile
    echo -e "\e[1;33m--Warning-- This file should be re-created" \
        "ASAP." >> $logFile
    echo -e "\e[1;33m--Warning-- Web users will NOT be notified the" \
        "server is down.\e[0m" >> $logFile
    echo -e "Script will continue processing..." >> $logFile
fi

## Put NextCloud in maintenance mode
echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Putting NextCloud" \
    "in maintenance mode..." >> $logFile
sudo -u ${webUser} php ${ncroot}/occ maintenance:mode --on >> $logFile 2>&1
# verify
if [ "$?" = "0" ]; then
    echo -e "\e[0;36m...done\e[0m" >> $logFile
else
    echo -e "\e[1;31m--Error-- There was a problem putting NextCloud" \
        "into maintenance mode" >> $logFile
    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m" >> $logFile
    exit 100
fi

## Read sqlDetails file and extract necessary information
mapfile -t sqlParams < $sqlDetails

## Dump SQL
echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
    "Dumping SQL...\e[0m" >> $logFile
mysqldump --single-transaction -h${sqlParams[0]} -u${sqlParams[1]} \
    -p${sqlParams[2]} ${sqlParams[3]} > "$sqlDumpDir/$sqlDumpFile" 2>> $logFile
# verify
if [ "$?" = "0" ]; then
    echo -e "\e[0;36m...done\e[0m" >> $logFile
else
    echo -e "\e[1;31m--Error-- There was a problem dumping SQL." >> $logFile
    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m" >> $logFile
    exit 201
fi

## Ready for Borg
echo -e "\e[1;39m[`date +%Y-%m-%d` `date +%H:%M:%S`] Pre-backup tasks" \
    "completed... calling BorgBackup" >> $logFile

## Generate and export variables required for BorgBackup
export BORG_BASE_DIR="$borgBaseDir"
export BORG_REMOTE_PATH="$borgRemotePath"
export BORG_RSH="ssh -i $borgRemoteSSHKeyfile"
export BORG_REPO="$(head -1 $borgDetails)"
export BORG_PASSPHRASE="$(tail -1 $borgDetails)"

## Process borgXtraFiles into array variable
mapfile -t xtraFiles < $borgXtraFiles

## Call BorgBackup
borg --show-rc create --list --exclude-from $borgExcludeFiles \
    --checkpoint-interval $borgCheckpoint ::`date +%Y-%m-%d_%H%M%S` \
    "${xtraFiles[@]}" \
    "$ncdata" \
    "$sqlDumpDir/$sqlDumpFile" 2>> $logFile

# Report BorgBackup exit status
if [ "$?" = "0" ]; then
    echo -e "\e[1;32m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Success--" \
        "BorgBackup completed successfully.\e[0m" >> $logFile
elif [ "$?" = "1" ]; then
    echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
        "BorgBackup completed with WARNINGS." >> $logFile
    echo -e "--Warning-- Please check Borg's output.\e[0m" >> $logFile
else
    echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Error--" \
        "BorgBackup encountered a serious ERROR." >> $logFile
    echo -e "--Error-- Please check Borg's output.\e[0m" >> $logFile
fi

## Have BorgBackup prune the repo to remove old archives
borg --show-rc prune -v --list ${borgPrune} :: 2>> $logFile

# Report BorgBackup exit status
if [ "$?" = "0" ]; then
    echo -e "\e[1;32m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Success--" \
        "BorgBackup PRUNE operation completed successfully.\e[0m" >> $logFile
elif [ "$?" = "1" ]; then
    echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
        "BorgBackup PRUNE operation completed with WARNINGS." >> $logFile
    echo -e "--Warning-- Please check Borg's output.\e[0m" >> $logFile
else
    echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Error--" \
        "BorgBackup PRUNE operation encountered a serious ERROR." >> $logFile
    echo -e "--Error-- Please check Borg's output.\e[0m" >> $logFile
fi

## Put NextCloud back into operational mode
echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Taking NextCloud" \
    "out of maintenance mode..." >> $logFile
sudo -u ${webUser} php ${ncroot}/occ maintenance:mode --off >> $logFile 2>&1
# verify
if [ "$?" = "0" ]; then
    echo -e "\e[0;36m...done\e[0m" >> $logFile
else
    echo -e "\e[1;31m--Error-- There was a problem taking NextCloud" \
        "out of maintenance mode" >> $logFile
    echo -e "This MUST be done manually or NextCloud will not" \
        "function!\e[0m" >> $logFile
    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m" >> $logFile
    exit 101
fi

## Remove 503 error page from webroot so NGINX serves web clients again
echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Removing 503 error page" \
    "from webroot...\e[0m" >> $logFile
rm -f "$webroot/$err503FileName" &>> $logFile
# verify actually removed
if [ -e "$webroot/$err503FileName" ]; then
    echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
        "Error removing 503 error page from webroot." >> $logFile
    echo -e "--Warning-- NGINX will NOT server webclients until this file is" \
        "removed.\e[0m" >> $logFile
    echo -e "Script will continue processing..." >> $logFile
else
    echo -e "\e[0;36m...done\e[0m" >> $logFile
fi

## Remove sqlDump file
echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Removing sqlDump" \
    "file...\e[0m" >> $logFile
rm -f "$sqlDumpDir/$sqlDumpFile" &>> $logFile
# verify actually removed
if [ -e "$sqlDumpDir/$sqlDumpFile" ]; then
    echo -e "\e[1;33m[`date +%Y-%m-%d` `date +%H:%M:%S`] --Warning--" \
        "Error removing sqldump file.  Please remove manually.\e[0m" >> $logFile
    echo -e "Script will continue processing..." >> $logFile
else
    echo -e "\e[0;36m...done\e[0m" >> $logFile
fi

## Log completion of script
echo -e "\e[1;32m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
    "--Backup operations completed--\e[0m" >> $logFile


# Gracefully exit
exit 0