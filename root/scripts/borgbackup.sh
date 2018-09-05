#!/bin/bash

#######
### Backup NextCloud13 installation to external repo using Borg Backup
### Assuming both NextCloud & Borg setups as outlined in their respecitive
### series at https://mytechiethoughts.com
###
### Events:
### 1. Copy 503 error page to stop NGINX from serving web clients.
###       (this depends on a complementary NGINX configuration)
### 2. Put NextCloud in maintenence mode to prevent logins and changes.
### 3. SQLdump from NextCloud.
### 4. Borg backup all files from xtraLocations.
### 5. Borg backup NextCloud data and files.
### 6. Put NextCloud back into operating mode.
### 7. Delete 503 error page so NGINX can serve web clients again.
#######


### Script variables -- please ensure they are accurate!

# FULL path to NGINX webroot (default: /usr/share/nginx/html)
webroot=/usr/share/nginx/html

# FULL path to NextCloud root directory
# By default, this is a folder within your webroot. If you setup is different
# then provide the FULL path here
# (default: webroot/nextcloud)
ncroot="$webroot/nextcloud"

# name of 503-error page (default: 503-error.html)
# MUST be in the same directory as THIS script
err503FileName=503-backup.html

# desired directory for SQLdump -- will be created if necessary
# (default: /SQLdump)
sqlDumpDir=/SQLdump

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

