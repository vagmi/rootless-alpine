# Union Filesystems (OverlayFS)

Containers are famous for their speed. A big part of this speed comes from **Copy-on-Write (CoW)** filesystems. I don't copy the entire operating system every time I start a container; I just layer a writable sheet on top of the read-only image.

## The Layer Cake

OverlayFS is the standard union filesystem used today. It merges multiple directories into one.

### The Components

1.  **LowerDir (Read-Only)**:
    This is the base image (e.g., Alpine Linux contents). It is never modified.
    *Example*: `/home/vagmi/.local/containers/alpine-box/rootfs` (original state)

2.  **UpperDir (Read-Write)**:
    This is the "diff" layer. Any file I create or modify goes here.
    *Example*: `/home/vagmi/.local/containers/alpine-box/overlay/upper`

3.  **WorkDir (Internal)**:
    A scratchpad directory required by OverlayFS for atomic operations.
    *Example*: `/home/vagmi/.local/containers/alpine-box/overlay/work`

4.  **MergedDir (The View)**:
    This is the final mount point the container sees.
    *Example*: `/home/vagmi/.local/containers/alpine-box/rootfs` (mounted state)

### How Operations Work

*   **Reading a file**: The kernel looks in `UpperDir`. If not found, it looks in `LowerDir`.
*   **Modifying a file**: The kernel **copies** the file from `LowerDir` to `UpperDir` (this is the "Copy" in "Copy-on-Write"), and then applies the modification to the copy.
*   **Creating a file**: It is created directly in `UpperDir`.
*   **Deleting a file**: A "Whiteout" file (a special 0/0 character device) is created in `UpperDir`. This tells the kernel "mask this file from LowerDir".

## The Rootless Challenge

Mounting an OverlayFS usually requires `CAP_SYS_ADMIN` in the initial namespace (i.e., root).

```bash
mount -t overlay overlay -o lowerdir=...,upperdir=... merged
# Error: Operation not permitted
```

### Solution 1: Kernel Support (User Namespaces)

Since Linux kernel 5.11, unprivileged users can mount OverlayFS **if** they are inside a User Namespace. This is why my script waits until the User Namespace is created before attempting the mount.

### Solution 2: FUSE-OverlayFS

Before kernel 5.11, or for complex UID mapping scenarios, I use **FUSE-OverlayFS**. This is a userspace implementation.

**Why FUSE?**
The native kernel OverlayFS has limitations with UID mapping.
*   The `LowerDir` usually contains files owned by root (UID 0).
*   On the host, these are just files owned by `vagmi` (UID 1000).
*   Inside the container, I want them to look like UID 0.

FUSE-OverlayFS is smarter about this shifting. It can actively translate UIDs on the fly, ensuring that `chown` works as expected inside the container without actually changing the ownership of the source files on the host disk in a way that breaks things.

This is why, in my final script, using `fuse-overlayfs` inside the user namespace was the most robust solution.
