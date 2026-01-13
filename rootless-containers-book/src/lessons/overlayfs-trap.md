# The OverlayFS Mount Trap

This was the most persistent hurdle in my journey.

## The Symptom
I tried to mount the filesystem. I had `fuse-overlayfs` installed. I had my directories ready.
Yet, every time I ran the script:
```
fusermount3: mount failed: Operation not permitted
```
Or, if I tried to use `mount -t overlay`, it simply failed silently or with "Permission Denied".

## The Mental Model Failure
I assumed that because I created the **User Namespace** (which gives me `CAP_SYS_ADMIN`), I could just mount the filesystem from my script's main process context.

I forgot that **capabilities are scoped to the namespace**.

## The Reality
1.  My script (running as `vagmi`) created a User Namespace.
2.  But the *script process itself* was still running in the **Host Namespace**.
3.  When I ran `fuse-overlayfs` from the script, it was trying to execute on the host.
4.  The host kernel looked at `vagmi` (UID 1000) and said: *"You are not root. You cannot mount filesystems."*

## The Solution: `nsenter` is the Key

I had to fundamentally restructure the script. Instead of preparing the filesystem *before* starting the container process, I had to move the mounting logic **inside** the container creation flow.

I used `nsenter` to inject the `fuse-overlayfs` command into the User Namespace I just created.

```bash
# Wrong (Host context)
fuse-overlayfs -o ... "$ROOTFS"

# Right (Namespace context)
nsenter --user -t $USERNS_PID fuse-overlayfs -o ... "$ROOTFS"
```

Once inside the namespace:
1.  I am effectively `root`.
2.  I have the necessary capabilities.
3.  The UID mapping is active, allowing `fuse-overlayfs` to translate the file ownership correctly (making host files owned by UID 1000 appear as UID 0).
