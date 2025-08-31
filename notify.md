# Script `notify.sh`

Universal notification sender via [ntfy](https://ntfy.sh/).
It also logs success or failure using the logging function from `log.sh`

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
notify "Door is still open!" "Door status" "door,warning" 4
```

**Behavior:**

* Sends notification to the topic defined by `NTFY_TOPIC`
    
* Logs success / failure messages using `log.sh`
    
* Echoes the message to stdout for immediate feedback
