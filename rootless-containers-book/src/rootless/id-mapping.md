# User Namespaces & ID Mapping

This is the engine room of rootless containers. It is the mechanism that allows a process to feel like `root` inside a container while remaining a standard, unprivileged user on the host.

## The Illusion of Root

Inside the container, I want files to look like they are owned by `root` (UID 0), `bin` (UID 1), `daemon` (UID 2), etc.
Outside the container, on the shared host system, I cannot actually let a user own files as root. That would be a massive security hole.

**User Namespaces** solve this by creating a translation layer (a map) between the UIDs inside the container and the UIDs on the host.

## The UID Map (`/proc/self/uid_map`)

When a process is in a User Namespace, it has a file `/proc/self/uid_map`.
This file contains three numbers per line:
`[Inside-ID] [Outside-ID] [Length]`

### A Simple Map (Single User)

If I just map my own user:
```
0 1000 1
```
*   **Inside ID 0** (Container Root) maps to **Outside ID 1000** (Vagmi).
*   Length is 1.

This works for basic things. `whoami` inside says "root". But if I try to `chown` a file to user `nobody` (UID 65534), it fails. Why? Because I only mapped ONE id. I don't have permission to be UID 65534 on the host.

## The Subuid/Subgid Mechanism

To run a full Linux distro, a container needs to own thousands of UIDs (for `postgres`, `nginx`, `www-data`, etc.).

Since a normal user (UID 1000) only owns *one* UID, system administrators grant them a range of **Subordinate UIDs** (subuids).

These are defined in `/etc/subuid`:
```
vagmi:100000:65536
```
This grants user `vagmi` ownership of 65,536 UIDs starting from ID 100,000.

### The Complex Map (Full Distro)

To support a full container, I create a map with **two** ranges:

1.  **Map Root**: Container UID 0 -> Host UID 1000.
2.  **Map Users**: Container UIDs 1..65536 -> Host UIDs 100000..165535.

The command `newuidmap` (a setuid helper binary) writes this to the kernel:

```bash
# newuidmap <pid> 0 1000 1 1 100000 65536
```

Resulting `uid_map`:
```
0       1000    1
1       100000  65536
```

### Visualizing the Mapping

| Container Reality (Inside) | Host Reality (Outside) |
|----------------------------|------------------------|
| `root` (UID 0)             | `vagmi` (UID 1000)     |
| `bin` (UID 1)              | `100000`               |
| `daemon` (UID 2)           | `100001`               |
| `nobody` (UID 65534)       | `165533`               |

## The `newuidmap` Security Gate

You might ask: *"Why can't I just write any mapping I want?"*

The kernel allows a user to write to their own `uid_map`, **BUT** they can only map UIDs they actually own (which is usually just their own current UID).

To map the range 100,000+, I need privilege.
This is why `newuidmap` has the **SUID bit** set (owned by root, executable by users).
1.  `newuidmap` starts as root.
2.  It checks `/etc/subuid`.
3.  Does `vagmi` own the range 100,000-165536?
4.  If yes, it writes the privileged mapping to `/proc/[pid]/uid_map`.

This mechanism delegates the ability to isolate specific ID ranges without giving full root access.
