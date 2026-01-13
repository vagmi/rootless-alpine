# Introduction

Welcome to "Rootless Containers from Scratch".

This book documents my journey of building a functional, rootless container implementation using nothing but standard Linux utilities and Bash.

## Why this book?

While tools like Docker and Podman abstract away the complexity of containers, understanding the underlying mechanisms is crucial for security engineers, system administrators, and curious developers. 

In this book, I dissect:
- How containers are just fancy Linux processes.
- The security implications of running as root vs. rootless.
- The specific hurdles encountered when implementing this in a shell script.

## Resources

*   **Source Code**: The script and book source are available at [https://github.com/vagmi/rootless-alpine](https://github.com/vagmi/rootless-alpine).
*   **Hosted Book**: You are likely reading this at [https://rootless.vagmi.ca](https://rootless.vagmi.ca).

## License

This work is licensed under a [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](LICENSE.md).
