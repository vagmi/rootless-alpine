# Obtaining the Image

In the Docker world, `docker pull` does a lot of work. I am going to break it down using lower-level "OCI" (Open Container Initiative) tools: **Skopeo** and **Umoci**.

## Step 1: Download (Skopeo)
An "Image" is really just a tarball (zip file) of a filesystem, plus a JSON file describing metadata (like "run `/bin/sh` by default").

I use `skopeo copy` to fetch this from a registry (like Docker Hub) to my local disk.
```bash
skopeo copy docker://alpine:latest oci:local-image:latest
```
This saves the blobs to a directory. At this point, it's just a pile of data - you can't "cd" into it yet.

## Step 2: Unpack (Umoci)
I need to turn that blob of data into a real folder with real files (`/bin`, `/etc`, `/home`). This is called "unpacking" or "extracting" the rootfs.

I use `umoci unpack`.

### The Ownership Problem
This is the trickiest part of rootless images.

1.  **The Source**: The Alpine image contains files owned by `root` (UID 0).
2.  **The Destination**: I am downloading this to `/home/vagmi/my-container`.
3.  **The Conflict**: User `vagmi` cannot create files owned by `root`. Only root can do that.

**How Umoci handles it**:
If I run `umoci unpack --rootless`, it extracts the files owned by *me* (UID 1000), but it records the *intended* ownership in a separate metadata file.

**My Fallback (Tar)**:
If I don't have `umoci`, I use `tar`. But `tar` will just make `vagmi` own everything.
This causes issues later because programs like `sudo` or `apk` expect to be owned by root.
*   **Fix**: I rely on the User Namespace mapping later to "shift" these UIDs so they *appear* correct inside the container.
