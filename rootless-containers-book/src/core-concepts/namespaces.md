# Namespaces: The Seven Kingdoms

Linux Namespaces are the fundamental isolation primitive of containers. They wrap a global system resource in an abstraction that makes it appear to the processes within the namespace that they have their own isolated instance of the global resource.

While there are several namespaces, seven are crucial for containers.

## The Big 7

| Namespace | Flag | Isolates | Purpose in Containers |
|-----------|------|----------|-----------------------|
| **User** | `CLONE_NEWUSER` | User & Group IDs | Allows a process to run as `root` inside while being a normal user outside. |
| **Mount** | `CLONE_NEWNS` | Mount points | Provides a separate filesystem view (the rootfs). |
| **PID** | `CLONE_NEWPID` | Process IDs | Ensures the container's init process sees itself as PID 1. |
| **Network** | `CLONE_NEWNET` | Network stack | Gives the container its own IP, localhost, and routing table. |
| **UTS** | `CLONE_NEWUTS` | Hostname | Allows the container to have its own hostname. |
| **IPC** | `CLONE_NEWIPC` | IPC resources | Prevents shared memory attacks between host and container. |
| **Cgroup** | `CLONE_NEWCGROUP` | Cgroup root | Isolates the view of cgroup hierarchy (less commonly used directly). |

## The User Namespace: The Key to Rootless

The **User Namespace** is special. It is the *only* namespace that an unprivileged user can create without `sudo`.

When creating a new User Namespace:
1.  I become UID 0 (root) *inside* that namespace.
2.  I gain a full set of Capabilities (like `CAP_SYS_ADMIN`, `CAP_NET_ADMIN`) *but only within that namespace*.

This is the magic trick:
> "To perform privileged operations (like mounting filesystems or configuring networks), I don't need to be real root. I just need to be root inside a User Namespace."

### Example: Becoming Root (Fake)

Try this in your terminal:

```bash
# -U: User Namespace
# -r: Map current user to root inside
unshare -U -r whoami
```

Output:
```
root
```

You are now root! (Well, technically, you are root inside that ephemeral namespace).

## Manipulating Namespaces

I use two primary syscalls (wrapped by command-line tools) to manage namespaces.

### 1. `unshare` (Create)

The `unshare` command creates new namespaces and then executes a program inside them.

In my rootless script:
```bash
unshare --user --fork --map-root-user bash
```
This creates a new user namespace and runs bash inside it.

### 2. `nsenter` (Join)

The `nsenter` command allows an existing process to "enter" the namespaces of another process. This is how `docker exec` works.

Every process has a directory in `/proc/[pid]/ns/` containing links to its namespaces:

```bash
ls -l /proc/$$/ns/
# lrwxrwxrwx 1 vagmi vagmi 0 Jan 12 10:00 net -> 'net:[4026531992]'
# lrwxrwxrwx 1 vagmi vagmi 0 Jan 12 10:00 user -> 'user:[4026531837]'
```

To join a container, I target its PID:

```bash
nsenter --target $CONTAINER_PID --mount --net --pid /bin/sh
```

## The Order of Operations

In my rootless implementation, the order matters immensely:

1.  **Create User Namespace**: I must do this *first* to gain the privileges needed to create the others.
2.  **Become Root (Inside)**: I map my host UID to root.
3.  **Create Other Namespaces**: Now that I am "root", I can create Mount, Network, and PID namespaces.
4.  **Mount Filesystems**: I mount `/proc`, `/sys`, and my `overlayfs` root.

If I tried to create a Mount namespace (`unshare -m`) before the User namespace, the kernel would deny me because I am not real root.
