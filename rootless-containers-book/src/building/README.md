# Building the Container: The Assembly Line

If you have used Docker, you are used to typing `docker run alpine` and having everything - downloading, unpacking, networking, mounting - happen instantly.

In this chapter, I am going to build that "run" command from scratch, using a bash script. I am stepping away from the "magic" and looking at the raw assembly line.

## The Process

Building a rootless container involves four distinct phases:

1.  **Preparation**: Ensuring the host Linux system allows me (a regular user) to perform the necessary magic.
2.  **Acquisition**: Getting the Operating System files (the "Image") and unpacking them onto my disk.
3.  **Storage Assembly**: Creating the "copy-on-write" filesystem layer so the container can write files without corrupting the original image.
4.  **Wiring**: Connecting the isolated container to the outside world (the internet).

## The Script

I will reference my `rootless-alpine.sh` script throughout this section. Think of this script as my custom-built container engine - a tiny, 400-line version of Docker.
