# Permission Conflicts & `resolv.conf`

One of the final errors I hit was deceptively simple:
```
/etc/resolv.conf: Permission denied
```

## The Context
I needed to configure DNS for the container. The standard way is to write `nameserver 10.0.2.3` into `/etc/resolv.conf` inside the container's rootfs.

## The Attempt (Failed)
My script tried to do this from the host:
```bash
echo "nameserver ..." > $ROOTFS/etc/resolv.conf
```

## The Permission Paradox
1.  **On Disk**: The file is physically owned by `vagmi` (UID 1000).
2.  **The Error**: So why can't `vagmi` write to it?

The issue was **OverlayFS** combined with **User Namespaces**.
Once the OverlayFS is mounted, it presents a unified view. If `fuse-overlayfs` is doing its job correctly, it tells the host kernel: *"This file is owned by UID 100000 (the mapped root)"*.

When my script (running as UID 1000) tries to write to it through the mount point, the permission check fails because UID 1000 != UID 100000.

## The Solution: Write from Within
I moved the configuration step **inside** the `start_rootless_container` function, which runs inside the namespace.

Inside the namespace:
1.  I am UID 0 (Root).
2.  The file appears to be owned by UID 0.
3.  The write succeeds.

This reinforces the core lesson: **Rootless containers are a separate world.** You cannot simply reach in from the outside and change things; you must enter the world (the namespace) to make changes.
