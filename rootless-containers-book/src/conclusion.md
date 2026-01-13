# Conclusion

I have successfully built a working rootless container runtime in just over 400 lines of Bash.

It works. It downloads an image, creates secure namespaces, maps UIDs, sets up a writable filesystem, and establishes networking. It allows a regular user to run a full Alpine Linux environment safely.

## Reflections: Clunky but Doable

Comparing this experience to FreeBSD Jails (which have existed since 2000) is illuminating.

*   **FreeBSD Jails**: Feel like a cohesive, designed feature of the OS. You define a jail in a config file, and the OS handles it. It feels "solid".
*   **Linux Rootless Containers**: Feel like a "Rube Goldberg machine". I am gluing together disparate features - Namespaces, Cgroups, OverlayFS, Slirp4netns, Setuid helpers - using shell scripts and hope.

The Linux approach is **composable** but **clunky**. It requires a deep understanding of how six or seven different subsystems interact. A single misstep in the order of operations (like creating the mount namespace before the user namespace) causes the whole house of cards to collapse with opaque "Permission Denied" errors.

## But... It's Magic

Despite the complexity, the result is magical.

To be able to become `root` - to install packages, modify network routes, and mount filesystems - without actually having `sudo` access to the host machine is a triumph of kernel engineering.

It opens the door for:
*   **Secure CI/CD pipelines** that don't need privileged runners.
*   **AI Agents** that can write and execute code without endangering the user.
*   **Desktop App Sandboxing** (like Flatpak) that works for everyone.

The complexity I faced is exactly why tools like Docker, Podman, and containerd exist: to wrap this complexity in a friendly API. But now, having built it myself, I understand exactly what those tools are doing for me.
