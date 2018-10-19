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

#### -d, NextCloud data directory

This is the full path to the location where NextCloud actually stores data.  In
a setup such as I recommend on my blog at
[https://mytechiethoughts.com](https://www.mytechiethoughts.com), you would be
using an entry such as *'/var/nc_data'*.  This directory and all subdirectories
automatically included in the backup.

#### -n, NextCloud webroot

This is the directory in which NextCloud's php and html files are located.  It
is generally somewhere under your webroot directory.  This is required so the
script can find the 'OCC' command to invoke maintenance mode.

#### -w, webuser account

This is the account that NextCloud runs under via your webserver.  This is
almost always *'www-data'*.  You would have to check your NGINX/Apache config to
be sure.  'OCC' will not run as any other user thus, the script cannot
enter/exit maintenance mode with knowing what user to emulate.

### Optional parameters

#### -5 _path/to/filename.html_, path to 503 html error page

The path to an html file for the script to copy to your webroot during the
backup process.  This file can be scanned by your webserver and a 503 error can
be issued to users letting them know that your NextCloud is 'temporarily
unavailable' while being backed up.  A sample 503 page is included for you.

If you remove the default file or the one you specify is missing, a warning will
be issued by the script but, it will continue executing.  More details on the
503 notification can be found later in the [503 functionality]() section of this
document. **Default: _scriptpath/503.html_**

#### -b _path/to/filename.file_, path to borg details file

This is a text file that lays out various borg options such as repo name,
password, additional files to include, exclusion patters, etc.  A sample file is
included for your reference.  More details, including the *required order* of
entries can be found later in this document in the [borg details file]()
section.
**Default: _scriptpath/nc_borg.details_**

#### -l _path/to/filename.file_, log file location

If you have a particular place you'd like this script to save it's log file,
then you can specify it using this parameter.  I would recommend *'/var/log'*.
By default, the script will name the log file *scriptname*.log and will save it
in the same directory as the script itself.
**Default: _scriptpath/scriptname.log_**

#### -s _path/to/filename.file_, path to SQL details file

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

#### -w _path_, path to webroot

This is the path to the directory your webserver is using as it's default root.
In other words, this is the directory that contains the html files served when
someone browses to your server.  Depending on your setup, this might be the same
as your NextCloud webroot.

This is used exclusively for 503 functionality since the script has to know
where to copy the 503 file.  If you don't want to use this functionality, you
can omit this parameter and the script will issue a warning and move on.  More
details can be found in the [503 functionality]() section later in this
document.