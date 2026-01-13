# Core Concepts

Before diving into the code, I needed to understand the three pillars of Linux containers:

1. **Namespaces**: Configuring what a process *sees*.
2. **Cgroups**: Configuring what a process can *use*.
3. **Union Filesystems**: Configuring how files are *layered*.

## The Traditional Model (with root)

To appreciate the complexity of rootless containers, it helps to understand how "normal" containers (like standard Docker or containerd) work.

In the traditional model, a daemon runs with **root privileges** on the host. This simplifies everything:

1.  **Creation**: The daemon calls `unshare()` or `clone()` to create namespaces. Since it is root, the kernel allows this immediately.
2.  **Networking**: The daemon creates a "veth pair" (virtual ethernet cable). It plugs one end into a host bridge (like `docker0`) and moves the other end into the container. It modifies `iptables` for NAT. All of this requires `CAP_NET_ADMIN` on the host.
3.  **Filesystem**: The daemon mounts OverlayFS directly. Since it is root, it ignores the ownership of the files on disk. It can read/write anything.
4.  **Cgroups**: The daemon writes directly to `/sys/fs/cgroup/...`.
5.  **User Switching**: Finally, if the container is supposed to run as a specific user (like `postgres`), the daemon performs the namespace setup and then "drops" privileges using `setuid()` before executing the payload.

### The Rootless Difference

In a rootless environment, I don't have a privileged daemon. I am just `vagmi` (UID 1000).

*   I cannot create a bridge device.
*   I cannot mount OverlayFS on host directories owned by root.
*   I cannot modify Cgroup limits (unless delegated).
*   I cannot write to `iptables`.

This forces me to use "User Namespaces" as a wedge to gain *fake* root privileges, and user-space tools (like `slirp4netns` and `fuse-overlayfs`) to emulate kernel features I cannot access.
