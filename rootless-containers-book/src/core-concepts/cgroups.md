# Control Groups (Cgroups)

While Namespaces isolate *visibility* (what you can see), Control Groups (cgroups) isolate *usage* (what you can use). They are the resource management layer of the kernel.

## Hierarchy and Controllers

Cgroups are organized in a hierarchy (a tree), similar to a filesystem. Directories in this tree represent groups of processes.

**Controllers** are the subsystems that enforce limits. Common controllers include:
*   **memory**: Limits RAM usage.
*   **cpu**: Limits CPU cycles.
*   **io**: Limits disk I/O bandwidth.
*   **pids**: Limits the total number of processes.

## Cgroup v1 vs. v2

Linux is transitioning from v1 to v2.

*   **Cgroup v1**: Had a separate hierarchy for each controller (`/sys/fs/cgroup/memory`, `/sys/fs/cgroup/cpu`, etc.). This was messy and hard to coordinate.
*   **Cgroup v2**: Has a **Unified Hierarchy** (`/sys/fs/cgroup`). All controllers exist in the same tree. This is what modern container runtimes (and my script) use.

## Rootless Delegation

Normally, only root can modify cgroups (e.g., set a memory limit). So how can a rootless user restrict their container's memory?

The answer is **Delegation**.

`systemd` (the init system) automatically creates a cgroup for every user login. It looks like this:
```
/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/
```

Systemd can "delegate" ownership of this directory (or a subdirectory) to the user. This means the directory is `chown`ed to the user (`vagmi:vagmi`).

Once I own the directory, I can create sub-directories (sub-cgroups) and write to their control files.

### Implementing Limits

In my script, I create a sub-cgroup for the container:

```bash
CGROUP_PATH="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/alpine-box"
mkdir -p "$CGROUP_PATH"
```

Then I enable controllers and set limits by writing to files:

1.  **Add Process**: Move the container's PID into the cgroup.
    ```bash
    echo $CONTAINER_PID > "$CGROUP_PATH/cgroup.procs"
    ```

2.  **Set Memory Limit**: Limit to 500MB.
    ```bash
    echo "500M" > "$CGROUP_PATH/memory.high"
    ```

3.  **Set CPU Limit**: Limit to 50% of one core (50000us out of 100000us).
    ```bash
    echo "50000 100000" > "$CGROUP_PATH/cpu.max"
    ```

## The "No Permission" Warning

If you see a warning about permissions when setting cgroups, it's usually because:
1.  You are using Cgroup v1 (which doesn't support safe delegation easily).
2.  Systemd hasn't delegated the controllers to your user session.

You can verify delegation with:
```bash
cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/cgroup.controllers
```
If this file is empty, your user cannot control cgroups.
