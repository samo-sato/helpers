# helpers
A collection of helper scripts for Linux systems.
Currently includes:
* `log` creates logs in file
* `notify` sends notifications using [ntfy](https://ntfy.sh/)

## Deployment

1. **Execute**

```bash
# Clone repo to location
sudo git clone https://github.com/samo-sato/helpers.git /opt/helpers

# Allow users to read/write the repo
sudo chmod -R 777 /opt/helpers

# Run the install script
./opt/helpers/utils/install.sh
# This should:
# - Create symlinks to individual helpers scripts to /usr/local/bin/ so the scripts could be run by typing just a script name in the terminal
# - Add hook file to be able to upgrade the local repo from remote repo with regullar OS upgrades
# - Create directory for logs /var/log/helpers and make it writable for users
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
Please refer to individual README files for each of the helper script
