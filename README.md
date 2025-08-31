# helpers
A collection of helper scripts for Linux systems.
Currently includes:
* `log` creates logs in file
* `notify` sends notifications using [ntfy](https://ntfy.sh/)

## Deployment

1. **Inside `/opt/` execute:**

```bash
# Copy scripts to desired location
git clone https://github.com/samo-sato/helpers.git

# Change directory
cd helpers

# Make scripts executable
sudo chmod +x *.sh

# Create directory for logs
sudo mkdir /var/log/helpers/

# Create log file
sudo touch /var/log/helpers/logs

# Make log file user writable
sudo chmod 666 /var/log/helpers/logs
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

3. **Create symlinks to the helper scripts (optional)**
```
sudo ln -s /opt/helpers/log.sh /usr/local/bin/log
sudo ln -s /opt/helpers/notify.sh /usr/local/bin/notify
```
This way you should be able to call the helpers from the terminal using simple keywords

4. **Test the helper scripts**
Please refer to individual README files for each of the helper script
