# Rootless Alpine

This project demonstrates how to build and run rootless Linux containers from scratch using standard CLI tools and Bash.

It consists of:
1.  **The Script**: `rootless-alpine.sh` - A ~400 line bash script that implements a functional container runtime (namespaces, cgroups, overlayfs, slirp4netns).
2.  **The Book**: A detailed guide explaining the architecture, the "why", and the "how".

## Links

*   **Source Code**: [https://github.com/vagmi/rootless-alpine](https://github.com/vagmi/rootless-alpine)
*   **Read the Book**: [https://rootless.vagmi.ca](https://rootless.vagmi.ca)

## Usage

```bash
./rootless-alpine.sh
```

## License

The code is open source. The book content is licensed under [CC-BY-NC-SA 4.0](rootless-containers-book/src/LICENSE.md).
