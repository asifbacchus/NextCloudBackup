#!/bin/bash

#######
### Backup NextCloud13 installation to external repo using Borg Backup
### Assuming both NextCloud & Borg setups as outlined in their respecitive
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
#######


### Script variables -- please ensure they are accurate!

# web user on your system (default: www-data)
webUser=www-data

# FULL path to NGINX webroot (default: /usr/share/nginx/html)
webroot=/usr/share/nginx/html

# FULL path to NextCloud root directory
# By default, this is a folder within your webroot. If you setup is different
# then provide the FULL path here
# (default: webroot/nextcloud)
ncroot="$webroot/nextcloud"

# NextCloud data directory
# If this is setup according to the blog series at https://mytechiethoughts.com
# then this is '/var/nc_data'.  If not, please change as appropriate for your
# environment.
# (default: /var/nc_data)
ncdata=/var/nc_data

# name of 503-error page (default: 503-error.html)
# MUST be in the same directory as THIS script
err503FileName=503-backup.html

# desired directory for SQLdump -- will be created if necessary
# (default: /SQLdump)
sqlDumpDir=/SQLdump

# FULL path to SQL details file (explained in blog)
# This is a 4 line file in the EXACT format:
#sqlHostMachineName
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

# FULL path to Borg repo details file (explained in blog)
# This is a 2 line file in the EXACT format:
# repo-name in format user@server.tld:repo
# passphrase
# This ensures no sensitive details are stored in this script :-)
# (default: borgBaseDir/repoDetails.borg)
borgDetails="$borgBaseDir/repoDetails.borg"

# FULL path to the extra source-list file (explained in blog)
# This file lists any extra files and directories that should be included
# in the backup along with the standard mailcow files/directories this script
# will be including.
# One source-entry per line.
# No spaces, comments or any other extraneous information, just the files/dirs
#    Directories must end with tailing slash
# (default: borgBaseDir/xtraLocations.borg)
borgXtraFiles="$borgBaseDir/xtraLocations.borg"

# Pruning options for borg archive (see BorgBackup documentation for details)
# This default example keeps all backups within the last 14 days, 12 weeks
# of end-of-week backups and 6 months of end-of-month backups.
borgPrune='--keep-within=14d --keep-weekly=12 --keep-monthly=6'

# desired name and location of log file for this script
# (default: /var/log/mailcow_backup.log)
logFile=/var/log/borgbackup.log


### Do NOT edit below this line


## Ensure script is running as root (required) otherwise, exit
#if [ $(id -u) -ne 0 ]; then
#    echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`] This script MUST" \
#        "be run as ROOT."
#    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m"
#    exit 1
#fi


### elevate script -- used during program testing
if [ $EUID != 0 ]; then
    sudo "$0" "$scriptPath"
    exit $?
fi


## Write script execution start in log file
echo -e "\e[1;32m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
    "--Begin backup operations--\e[0m" >> $logFile

## Parse supplied variables and determine additional script vars
scriptPath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
err503FullPath="$scriptPath/$err503FileName"

## Export logfle location for use by external programs
export logFile="$logFile"

## Check for sqlDumpDir and create if necessary
if [ -e $sqlDumpDir ]; then
    echo -e "\e[0m[`date +%Y-%m-%d` `date +%H:%M:%S`] Confirmed:" \
        "sqlDumpDir exists at \e[0;33m$sqlDumpDir\e[0m" >> $logFile
else
    echo -e "\e[0;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Creating:" \
        "\e[0;33m$sqlDumpDir\e[0;36m..." >> $logFile
    mkdir $sqlDumpDir &>> $logFile
    # confirm creation successful
    if [ -e $sqlDumpDir ]; then
        echo -e "...done\e[0m" >> $logFile
    else
        echo -e "\e[1;31m[`date +%Y-%m-%d` `date +%H:%M:%S`]" \
            "--Error-- There was a problem creating $sqlDumpDir." >> $logFile
        echo -e "\e[4;31m--Error-- Script aborted\e[0;31m.\e[0m" >> $logFile
        exit 101
    fi
fi

## Create unique filename for sqlDump file
sqlDumpFile="backup_${DBNAME}_`date +%Y%m%d_%H%M%S`.sql"
echo -e "\e[0m[`date +%Y-%m-%d` `date +%H:%M:%S`] mysql dump file will be" \
    "stored at:" >> $logFile
echo -e "\e[0;33m$sqlDumpDir/$sqlDumpFile\e[0m" >> $logFile

## Find 503 error page and copy to NGINX webroot
## File must be in the same location as this script
## IF file is not found, log warning but continue script
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
sudo -u ${webUser} php "${ncroot}/occ maintenance:mode --on" 2>> $logFile
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
    "Dumping SQL..." >> $logFile
mysqldump --single-transaction -h${sqlParams[0]} -u${sqlParams[1]} -p${sqlParams[2]} ${sqlParams[3]} > "$sqlDumpDir/$sqlDumpFile"
# verify
if [ "$?" = "0" ]; then
    echo -e "\e[0;36m...done\e[0m" >> $logFile
else
    echo -e "\e[1;31m--Error-- There was a problem dumping SQL." >> $logFile
    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m" >> $logFile
    exit 102
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
borg --show-rc create --list ::`date +%Y-%m-%d_%H%M%S` \
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
echo -e "\e[1;36m[`date +%Y-%m-%d` `date +%H:%M:%S`] Putting NextCloud" \
    "in maintenance mode..." >> $logFile
sudo -u ${webUser} php "${ncroot}/occ maintenance:mode --off" 2>> $logFile
# verify
if [ "$?" = "0" ]; then
    echo -e "\e[0;36m...done\e[0m" >> $logFile
else
    echo -e "\e[1;31m--Error-- There was a problem taking NextCloud" \
        "out of maintenance mode" >> $logFile
    echo -e "This MUST be done manually or NextCloud will not" \
        "function!\e[0m" >> $logFile
    echo -e "\e[4;31mScript aborted\e[0;31m.\e[0m" >> $logFile
    exit 102
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



# Gracefully exit
exit 0