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

