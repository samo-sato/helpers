# Helper script `log.sh`

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
log "Disk almost full!" "$0"
```

**Produces following log line**
```
2025-08-30 21:33 [-bash] Disk almost full!
```
**Log file location**
`/var/log/helpers/logs`
