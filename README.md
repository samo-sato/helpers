# sysutils
A collection of helper scripts to be used on Linux machines.  
Currently includes logging and NTFY notification utilities. Designed to be deployed in a central location and used across multiple machines.

## Deployment

1. **Inside `/usr/local/bin/` execute (*):**

(*) 🤔 not sure if this is good practice; maybe use different location
```bash
# Copy scripts to desired location
sudo git clone https://github.com/samo-sato/sysutils.git

# Change directory
cd sysutils

# Make scripts executable
sudo chmod +x notify.sh
sudo chmod +x log.sh

# Create log file and make it user writableg
sudo touch logs
sudo chmod 666 logs
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

## Scripts

### Script `log.sh`

Contains universal logging function.

**Parameters:**
1. Message
2. Name of the source of the message (optional)

**Usage:**
```bash
log.sh "{message}" "{optional calling source name}"
```
**Log format:**
`{timestamp} [{calling_script}] {message}`
If calling_script is not provided, the brackets are omitted.

**Example - command executed from terminal:**
```bash
/usr/local/bin/sysutils/log.sh "Disk almost full!" "$0"
```
**Produces following log line**
```
2025-08-30 21:33 [-bash] Disk almost full!
```

### Script `notify.sh`
Universal notification sender via [NTFY](https://ntfy.sh/)
It also logs in case of success or failure using logging function defined in `log.sh`

**Parameters:**
1. Message
2. Title (optional): default: "Notification"
3. Tags (optional):  comma-separated: "tag1,tag2"; example: "floppy_disk,warning"; full tag list: https://docs.ntfy.sh/emojis/
4. Priority (optional): default: 3; possible values: 1,2,3,4,5; higher = max priority

**Usage:**
```bash
notify.sh "{message}" "{optional title}" "{optional tags}" "{optional priority}"
```

**Example usage:**
```bash
/usr/local/bin/sysutils/notify.sh "Door is still open!" "Door status" "door,warning" 4
```

**Behavior:**

* Sends notification to the topic defined by `NTFY_TOPIC`
    
* Logs success / failure messages to `/usr/local/bin/sysutils/logs`
    
* Echoes the message to stdout for immediate feedback
