# NextCloud Backup using borgbackup

This script automates backing up your NextCloud installation using borgbackup
and a remote ssh-capable storage system.  I suggest using rsync.net since they
have great speeds and a special pricing structure for borgbackup/attic users
([details here](https://www.rsync.net/products/attic.html)).

This script automates the following tasks:

- Optionally copies a 503 error page to your webserver so users know when your
  server is unavailable due to backups being performed. The 503 file is removed
  when the backup is completed so users can login again
- Dumps mySQL database and adds it to the backup
- Handles entering and exiting NextCloud's maintenance mode to 'lock' accounts
  so changes are not made during the backup process
- Allows you to specify additional files you want backed up
- Allows you to specify files/directories to exclude from your backups (e.g.
  previews)
- Runs 'borg prune' to make sure you are trimming old backups on your schedule
- Creates an clear, easy to parse log file so you can easily keep an eye on your
  backups and any errors/warnings

## Environment notes

The script is designed to be easy to use but still be flexible enough to
accommodate a wide range of common NextCloud setups.  I have tested it with
NextCloud 13 and 14 using a standard LEMP setup (Debian Stretch, NGINX, mariaDB
& PHP7).  The script accepts several parameters to provide it with the settings
it requires to function.  In addition, it reads external files for SQL and borg
settings, so you don't have to weed through the script code to supply things
like passwords.

## Why root?

This script must be run by the root user and will exit with an error if you try
running it otherwise.  This is because NextCloud's OCC command (needed to put
NextCloud into maintenance mode) must be run as the web-user account and only
the root account can switch users without needing to stop and ask for
permission/passwords.

## Script parameters

You can run the script with the *'-?'* parameter to access the built-in help
which explains the parameters.  However, the following is more detailed
explanation of each parameter and how to use them.
**Note that any parameters needing a directory (webroot, nextcloud root, etc.)
can be entered with or without the trailing / since it's stripped by the script
anyways.**

General usage:

```Bash
/path/to/script/scriptname.sh -parameter argument -parameter argument ...
```

### Required parameters

#### -d _/path/to/data/_, NextCloud data directory

This is the full path to the location where NextCloud actually stores data.  In
a setup such as I recommend on my blog at
[https://mytechiethoughts.com](https://www.mytechiethoughts.com), you would be
using an entry such as *'/var/nc_data'*.  This directory and all subdirectories
automatically included in the backup.

#### -n _/path/to/nextcloud/_, NextCloud webroot

This is the directory in which NextCloud's php and html files are located.  It
is generally somewhere under your webroot directory.  This is required so the
script can find the 'OCC' command to invoke maintenance mode.

#### -w _accountName_, webuser account

This is the account that NextCloud runs under via your webserver.  This is
almost always *'www-data'*.  You would have to check your NGINX/Apache config to
be sure.  'OCC' will not run as any other user thus, the script cannot
enter/exit maintenance mode with knowing what user to emulate.

### Optional parameters

#### -5 _/path/to/filename.html_, path to 503 html error page

The path to an html file for the script to copy to your webroot during the
backup process.  This file can be scanned by your webserver and a 503 error can
be issued to users letting them know that your NextCloud is 'temporarily
unavailable' while being backed up.  A sample 503 page is included for you.

If you remove the default file or the one you specify is missing, a warning will
be issued by the script but, it will continue executing.  More details on the
503 notification can be found later in the [503 functionality]() section of this
document. **Default: _scriptpath/503.html_**

#### -b _/path/to/filename.file_, path to borg details file

This is a text file that lays out various borg options such as repo name,
password, additional files to include, exclusion patters, etc.  A sample file is
included for your reference.  More details, including the *required order* of
entries can be found later in this document in the [borg details file](#borg-details-file)
section.
**Default: _scriptpath/nc_borg.details_**

#### -l _/path/to/filename.file_, log file location

If you have a particular place you'd like this script to save it's log file,
then you can specify it using this parameter.  I would recommend *'/var/log'*.
By default, the script will name the log file *scriptname*.log and will save it
in the same directory as the script itself.
**Default: _scriptpath/scriptname.log_**

#### -s _/path/to/filename.file_, path to SQL details file

This is text file containing the details needed to connect to NextCloud's SQL
database.  For more information about the *required order* of entries can be
found later in this document in the [sql details file]() section.
**Default: _scriptpath/nc_sql.details_**

#### -v, verbose output from borg

By default, the script will ask borg to generate summary only output and record
that in the script's log file.  If you are running the backup for the first time
or are troubleshooting, you may want a detailed output of all files and their
changed/unchanged/excluded status from borg.  In that case, specify the -v
switch.
**Note: This will make your log file very large, very quickly since EVERY file
being backed up is written to the log.**

#### -w _/path/to/webroot/_, path to webroot

This is the path to the directory your webserver is using as it's default root.
In other words, this is the directory that contains the html files served when
someone browses to your server.  Depending on your setup, this might be the same
as your NextCloud webroot.

This is used exclusively for 503 functionality since the script has to know
where to copy the 503 file.  If you don't want to use this functionality, you
can omit this parameter and the script will issue a warning and move on.  More
details can be found in the [503 functionality]() section later in this
document.

### Borg details file

This file contains all the data needed to access your borg remote data repo.
Each line must contain specific information in a specific order or needs to be
blank if that data is not required.  The sample file includes this data and
example entries.  The file must have the following information in the following
order:

    1. path to borg base directory **(required)**
    2. path to ssh private key for repo **(required)**
    3. connection string to remote repo **(required)**
    4. password for ssh key/repo **(required)**
    5. path to file listing additional files/directories to backup
    6. path to file containing borg-specific exclusion patterns
    7. purge timeframe options
    8. location of borg remote instance

#### borg specific entries (lines 1-4)

If you need help with these options, then you should consult the borg
documentation or search my blog at
[https://mytechiethoughts.com](https://mytechiethoughts.com) for borg.

##### additional files/directories to backup

This points to a plain-text file listing additional files and directories you'd
like borg to include in the backup.  The sample file, *'xtraLocations.borg'*
contains the most likely files you'd want to include assuming you're using a
standard setup like it outline in my blog.

The following would include all files in the home folder for users *'foo'* and
*'bar'* and any conf files in *'/etc/someProgram'*:

```Bash
/home/foo/
/home/bar/
/etc/someProgram/*.conf
```

You can leave this line blank to tell borg to only backup your NextCloud data
directory and the SQL dump.  However, this is pretty unusual since you would not
be including any configuration files, webserver configurations, etc.  If you
omit this line, the script will log a warning in your log.

##### exclusion patterns

This points to a plain-text file containing borg-specific patterns describing
what files you'd like borg to ignore during the backup.  The sample file,
*'excludeLocations.borg'* contains a list of directories to exclude assuming a
standard NextCloud install -- the previews directory and the cache directory.
You need to run *'borg help patterns'* for help on how to specify any additional
exclusion patterns.

##### purge timeframe options

Here you can let borg purge know how you want to manage your backup history.
Consult the borg documentation and then copy the relevant options directly into
this line including any spaces, etc.  The example file contains the following as
a staring point:

```Ini
--keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1
```

This would tell borg prune to keep ALL backups made for any reason within the
last 7 days, keep 30 days worth of daily backups, 12 weeks of end-of-week
backups and then an infinite amount of end-of-month backups.

##### borg remote location

If you're using rsync, then just have this say *'borg1'*.  If you are using
another provider, you'll have to reference their locally installed copy of borg
relative to your repo path.  You can also leave this blank if your provider does
not run borg locally but your backups/restores will be slower.

##### Examples:

All fields including pointers to additional files to backup, exclusion patterns
and a remote borg path.  Prune: keep all backups made in the last 14 days.

```Ini
/var/borgbackup
/var/borgbackup/SSHprivate.key
myuser@server001.rsync.net:NCBackup/
myPaSsWoRd
/root/NCscripts/xtraLocations.borg
/root/NCscripts/excludeLocations.borg
--keep-within=14d
borg1
```

No exclusions, keep 14 days end-of-day, 52 weeks end-of-week

```Ini
/var/borgbackup
/root/keys/rsyncPrivate.key
myuser@server001.rsync.net:myBackup/
PaSsWoRd
/var/borgbackup/include.list

--keep-daily=14 --keep-weekly=52
borg1
```

Repo at root, no extra file locations, no exclusions, no remote borg installation. Keep last 30
backups.

```Ini
/root/.borg
/root/.borg/private.key
username@server.tld:backup/
pAsSw0rD


--keep-within=30d

```

### SQL details file

This file contains all the information needed to access your NextCloud SQL
database in order to dump it's contents into a file that can be easily
backed-up. Each line must contain specific information in a specific order.  The
sample file includes this data and example entries.  The file must have the
following information in the following order (**all entries required**):

    1. name of machine hosting mySQL (usually localhost)
    2. name of authorized user
    3. password for above user
    4. name of NextCloud database

For example:

```Ini
localhost
nextcloud
pAsSwOrD
nextcloudDB
```

#### Protect this file!

This file contains information on how to access your SQL installation therefore,
you **must** protect it.  You should lock it out to your root user.  Putting it
in your root folder is not enough!  Run the following commands to restrict access
to the root user only (assuming filename is *'nc_sql.details'*):

```Bash
# make root the owner
chown root:root nc_sql.details
# restrict access to root only
chmod 600 nc_sql.details
```
