# Prerequisites & Environment

Before I can build anything, I need to ensure my environment is compatible. Since we are developers, let's compare this to setting up a development environment.

## 1. The Kernel Features (`/proc/self/ns/user`)
Just as a Python script might check `sys.version` to ensure it's running on Python 3.10+, my container script checks for **User Namespace** support.

I check if `/proc/self/ns/user` exists.
*   **What it is**: This file represents the namespace of the current process.
*   **Why I need it**: If the kernel doesn't support User Namespaces, I cannot create my "fake root" environment. The game is over before it begins.

## 2. The Permission Helpers (`newuidmap` & `newgidmap`)
In a typical web app, you might need an API Key to access a third-party service. In Linux, these two binaries are our "API Keys" to the kernel's privileged ID mapping features.

*   **The Problem**: A normal user cannot map arbitrary UIDs (like mapping host UID 100000 to container UID 1). Only root can do that.
*   **The Solution**: These two programs have the **SUID bit** set. This means when you run them, they execute with `root` privileges, even if *you* are just a normal user.
*   **The Check**: My script verifies they are installed and have the SUID bit (`chmod u+s`).

## 3. The Allowance (`/etc/subuid`)
Think of `/etc/subuid` as an Access Control List (ACL) or a `permissions.json` file.

Just because I have the `newuidmap` tool doesn't mean I can use *any* ID. The system administrator must explicitly grant me a range of IDs to play with.

A line like `vagmi:100000:65536` says:
> "User 'vagmi' is allowed to use 65,536 IDs starting from 100,000."

If this file is missing or doesn't contain my user, my script cannot create the mapping, and the container will fail to start.
