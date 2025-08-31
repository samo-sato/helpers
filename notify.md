# Script `notify.sh`

Universal notification sender via [ntfy](https://ntfy.sh/).
It also logs success or failure using the logging function from `log.sh`

**Flags:**
* `-m`   Message text (required)
* `-t`   Title (optional): default: "Notification"
* `-g`   Tags (optional):  comma-separated: "tag1,tag2"; example: "floppy_disk,warning"; full tag list: https://docs.ntfy.sh/emojis/
* `-p`   Priority (optional): default: 3; possible values: 1,2,3,4,5; higher = max priority
* `-h`   Show this help message

**Example usage:**
```bash
./notify.sh -m "Door is still open!" -t "Door status" .g "door,warning" -p 4
```

**Behavior:**
* Sends notification to the topic defined by `NTFY_TOPIC`
* Logs success / failure messages using `log.sh`
