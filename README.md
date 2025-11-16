# helpers
A collection of helper scripts for Linux systems.
More detailed descriptions of individual tools are included within the tools themselves. Just use the `-h` or `--help` flag for any tool, or inspect the script directly.

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
# - Create /var/log/helpers and make it writable for users
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
