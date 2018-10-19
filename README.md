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

## Script parameters

