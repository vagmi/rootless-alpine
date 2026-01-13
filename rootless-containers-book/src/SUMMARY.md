# Rootless Containers from Scratch

[Introduction](introduction.md)

- [Core Concepts](core-concepts/README.md)
    - [Namespaces: The Seven Kingdoms](core-concepts/namespaces.md)
    - [Control Groups: Resource Management](core-concepts/cgroups.md)
    - [Union Filesystems: Layers](core-concepts/overlayfs.md)

- [The Rootless Revolution](rootless/README.md)
    - [Why Rootless?](rootless/why-rootless.md)
    - [User Namespaces & ID Mapping](rootless/id-mapping.md)

- [Building the Container](building/README.md)
    - [Prerequisites & Environment](building/environment.md)
    - [Obtaining the Image](building/images.md)
    - [The Filesystem Challenge](building/filesystem.md)
    - [Networking User Space](building/networking.md)

- [Lessons Learned](lessons/README.md)
    - [The OverlayFS Mount Trap](lessons/overlayfs-trap.md)
    - [Process Management & Waiting](lessons/process-management.md)
    - [Permission Conflicts](lessons/permissions.md)

[Conclusion](conclusion.md)
[License](LICENSE.md)
