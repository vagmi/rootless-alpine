# The Filesystem Challenge: OverlayFS

I have my unpacked image (the `rootfs`). Now, I want to run a container.
But wait! If I run the container directly in that directory, any changes I make (installing packages, creating files) will permanently modify the image. I don't want that. I want a fresh start every time.

## The Solution: OverlayFS
I use OverlayFS to create a "sandwich":

1.  **LowerDir (The Bread)**: My read-only `rootfs` (the Alpine image).
2.  **UpperDir (The Filling)**: An empty directory where my changes go.
3.  **MergedDir (The Sandwich)**: The magical view that combines them.

## The Rootless Twist

In a standard system, I would run:
```bash
mount -t overlay ...
```
But `mount` requires root.

### The "Permission Denied" Trap
If I try to run `mount` (or even `fuse-overlayfs`) from my regular user shell, it often fails.
Why? Because the files in `LowerDir` are owned by `vagmi` (UID 1000). But inside the container, I want them to look like UID 0.

If I mount it *outside*, the filesystem sees "Owner: 1000".
When I enter the container (where I am fake-root), I might not have the right permissions to modify them, or the ownership looks wrong.

### The Fix: Mount INSIDE the Namespace
This was the key breakthrough in my script.

I do **not** setup the mount before creating the container.
1.  I create the User Namespace first.
2.  I enter the namespace.
3.  **Then** I run `fuse-overlayfs`.

Because I am inside the namespace, `fuse-overlayfs` sees the UID mapping. It knows:
*   "Oh, the backing file on disk is owned by 1000."
*   "But inside here, 1000 is mapped to 0."
*   "So I will present this file to the user as owned by root."

This dynamic translation is what allows commands like `apk install` (which needs to chown files to root) to succeed.
