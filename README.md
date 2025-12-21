# helpers
A collection of helper scripts for Linux systems.
More detailed descriptions of individual tools are included within the tools themselves. Just use the `-h` or `--help` flag for any tool, or inspect the script directly.

## Available Tools

Below is a list of helper tools included in this repository along with a brief description of each:

- **backup.sh** - Backup management script to archive files based on retention policies
- **dirsize.sh** - Displays disk usage of directories in a human-friendly format
- **getvid.sh** - Downloads video content from a given URL; yt-dlp is used here
- **helpers.sh** - This is just to list all available helper tools like you see them here in this list
- **log.sh** - Centralized logging functions for consistent log formatting
- **notify.sh** - Sends notifications on your phone from shell scripts; ntfy is used here
- **pack.sh** - Creates compressed archives of specified files or directories
- **search.sh** - Searches files and text patterns across directories
- **sysinfo.sh** - Outputs system information
- **unpack.sh** - Extracts compressed archives into target locations

## Deployment

1. **Execute**

```bash
# As a user (without sudo), clone the repo to a temporary user location
git clone https://github.com/samo-sato/helpers.git ~/helpers

# As a user with sudo privileges, move the repo to /opt and run the install script
sudo mv ~/helpers /opt/helpers
sudo /opt/helpers/utils/install.sh

# This will:
# - Create symlinks to helper scripts in /usr/local/bin/ so they can be run by name
# - Add a hook to allow updating the local repo during regular OS upgrades
# - Create /var/log/helpers and make it writable for anyone
```

2. **Configure environment variable:**
- Make `NTFY_TOPIC` value unique enough to not get spammed
```bash
sudo nano /etc/environment
# Add:
NTFY_TOPIC="your-unique-topic-name"
# Save and exit
```
- Then, as Linux user, log out and log back in to load new environment variable to your shell

3. **Test the helper scripts**
- Run any helper tool with `-h` or `--help` to see usage and examples.
