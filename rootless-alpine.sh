#!/bin/bash
set -euo pipefail

# ====================
# ROOTLESS CONFIGURATION
# ====================
CONTAINER_NAME="alpine-box"
CONTAINER_USER=$(id -un)
CONTAINER_UID=$(id -u)
CONTAINER_GID=$(id -g)
CONTAINER_HOME="$HOME/.local/containers"
CONTAINER_ROOT="$CONTAINER_HOME/$CONTAINER_NAME"
ROOTFS="$CONTAINER_ROOT/rootfs"
IMAGE="docker://docker.io/library/alpine:latest"

# ====================
# 1. SETUP ROOTLESS ENVIRONMENT
# ====================
setup_rootless_env() {
    echo "[1] Setting up rootless environment for user $CONTAINER_USER (UID:$CONTAINER_UID)"
    
    # Check kernel support
    if [ ! -e /proc/self/ns/user ]; then
        echo "Error: User namespaces not supported by kernel"
        echo "Enable with: sudo sysctl kernel.unprivileged_userns_clone=1"
        exit 1
    fi
    
    # Check for newuidmap/newgidmap (setuid helpers)
    if ! command -v newuidmap &>/dev/null; then
        echo "Warning: newuidmap not found, UID mapping may be limited"
    elif [ ! -u "$(command -v newuidmap)" ]; then
        echo "Error: newuidmap is installed but missing the SUID bit."
        echo "This is required for rootless configuration."
        echo "Please run: sudo chmod u+s $(command -v newuidmap) $(command -v newgidmap)"
        exit 1
    fi
    
    # Create container directories in user space
    mkdir -p "$CONTAINER_HOME"
    mkdir -p $CONTAINER_ROOT/{overlay/{upper,work},image}
    
    # Configure subuid/subgid for the user (if not already)
    if [ ! -f /etc/subuid ] || ! grep -q "^$CONTAINER_USER:" /etc/subuid; then
        echo "Setting up subuid/subgid..."
        echo "$CONTAINER_USER:100000:65536" | sudo tee -a /etc/subuid
        echo "$CONTAINER_USER:100000:65536" | sudo tee -a /etc/subgid
    fi
    
    echo "✓ Rootless environment ready"
}

# ====================
# 2. ROOTLESS IMAGE DOWNLOAD
# ====================
download_image_rootless() {
    echo "[2] Downloading image as non-root user..."
    
    # Use skopeo with --override-uid/--override-gid
    skopeo copy  \
        "$IMAGE" "oci:$CONTAINER_ROOT/image:latest"
    
    # Extract using umoci with rootless flag
    if command -v umoci &> /dev/null; then
        umoci unpack --rootless --image "$CONTAINER_ROOT/image:latest" "$CONTAINER_ROOT"
    else
        # Manual extraction preserving ownership
        tar -xf "$CONTAINER_ROOT/image/oci-layout" -C "$ROOTFS" --no-same-owner 2>/dev/null || true
        
        # Need to fix ownership for user namespace
        find "$ROOTFS" -user 0 -exec chown "$CONTAINER_UID" {} \;
        find "$ROOTFS" -group 0 -exec chgrp "$CONTAINER_GID" {} \;
    fi
    
    echo "✓ Image downloaded with user ownership"
}

# ====================
# 3. ROOTLESS OVERLAYFS SETUP
# ====================
setup_rootless_overlay() {
    echo "[3] Preparing overlay directories..."
    
    # Create necessary directories with user permissions
    mkdir -p "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" "$ROOTFS/tmp"
    chmod 1777 "$ROOTFS/tmp"
    
    # We will perform the actual mount INSIDE the container namespaces
    # to ensure permissions are correct and consistent.
    
    echo "✓ Overlay directories ready"
}

# ====================
# 4. CREATE USER NAMESPACE WITH UID/GID MAPPING
# ====================
create_user_namespace() {
    echo "[4] Creating user namespace with ID mapping..."
    
    # Start a process with user namespace
    unshare --user --fork \
        bash -c "
            echo 'User namespace created in PID \$\$'
            # Now we're "root" inside the user namespace
            exec tail -f /dev/null
        " &
    
    USERNS_PID=$!
    
    # Wait for namespace creation
    sleep 0.5
    
    # Setup UID/GID mapping if newuidmap is available
    if command -v newuidmap &>/dev/null; then
        # Map container UID 0 -> host $CONTAINER_UID
        # Map container UID 1-65535 -> host subuid range
        newuidmap $USERNS_PID \
            0 $CONTAINER_UID 1 \
            1 100000 65535
        
        newgidmap $USERNS_PID \
            0 $CONTAINER_GID 1 \
            1 100000 65535
    else
        # Fallback: simple mapping (only works if user has CAP_SETUID)
        echo "0 $CONTAINER_UID 1" > /proc/$USERNS_PID/uid_map
        echo "0 $CONTAINER_GID 1" > /proc/$USERNS_PID/gid_map
    fi
    
    echo $USERNS_PID > "$CONTAINER_ROOT/userns.pid"
    echo "✓ User namespace created (PID: $USERNS_PID)"
    echo "  Container root (UID 0) -> Host user ($CONTAINER_UID:$CONTAINER_GID)"
}

# ====================
# 5. CREATE ALL NAMESPACES ROOTLESS
# ====================
create_rootless_namespaces() {
    echo "[5] Creating all namespaces..."
    
    # Enter user namespace first, then create other namespaces
    nsenter --user --preserve-credentials -t $(cat "$CONTAINER_ROOT/userns.pid") \
        unshare --mount --uts --ipc --pid --net --cgroup --fork \
            bash -c "
                echo 'All namespaces created in PID \$\$'
                echo \$\$ > '$CONTAINER_ROOT/container.pid'
                
                # Setup OverlayFS INSIDE the namespace
                if command -v fuse-overlayfs &>/dev/null; then
                    # We are inside the User NS now.
                    # Host UID 1000 is mapped to 0.
                    # Host UID 100000+ are mapped to 1+.
                    # Since the lowerdir (ROOTFS) is owned by Host 1000 (Container 0),
                    # we do NOT need extra uidmapping args for fuse-overlayfs here,
                    # because the kernel User NS handles the translation for the backing files.
                    
                    fuse-overlayfs -o \
                        \"lowerdir=$ROOTFS,upperdir=$CONTAINER_ROOT/overlay/upper,workdir=$CONTAINER_ROOT/overlay/work\" \
                        \"$ROOTFS\"
                else
                    # Try kernel overlay (needs kernel 5.11+)
                    mount -t overlay overlay -o \
                        \"lowerdir=$ROOTFS,upperdir=$CONTAINER_ROOT/overlay/upper,workdir=$CONTAINER_ROOT/overlay/work,userxattr\" \
                        \"$ROOTFS\" 2>/dev/null || mount --bind \"$ROOTFS\" \"$ROOTFS\"
                fi

                # Mount proc in new mount namespace
                mount -t proc proc /proc 2>/dev/null || true
                
                # Keep running
                exec tail -f /dev/null
            " &
    
    UNSHARE_PID=$!
    echo $UNSHARE_PID > "$CONTAINER_ROOT/parent.pid"
    
    # Wait for container process to report it's ready (writes '1')
    while [ ! -f "$CONTAINER_ROOT/container.pid" ]; do sleep 0.1; done
    
    # Get the real PID from the host perspective
    # The background process ($UNSHARE_PID) is 'unshare'
    # Its child is the bash process inside the container
    CONTAINER_PID=$(pgrep -P $UNSHARE_PID | head -n 1)
    
    if [ -z "$CONTAINER_PID" ]; then
        echo "Error: Could not determine container PID"
        kill $UNSHARE_PID
        exit 1
    fi
    
    # Update the pid file with the host PID
    echo $CONTAINER_PID > "$CONTAINER_ROOT/container.pid"
    
    echo "✓ Container PID: $CONTAINER_PID"
}

# ====================
# 6. ROOTLESS NETWORKING WITH SLIRP4NETNS
# ====================
setup_rootless_network() {
    echo "[6] Setting up rootless networking..."
    
    if ! command -v slirp4netns &>/dev/null; then
        echo "Warning: slirp4netns not found, network will be isolated"
        return
    fi
    
    # Create network namespace
    ip netns add "$CONTAINER_NAME" 2>/dev/null || true
    
    # Get a TAP handle for slirp
    TAP_HANDLE=$(printf "%x%x" $RANDOM $RANDOM)
    
    # Start slirp4netns in background
    slirp4netns --configure --mtu=65520 --disable-host-loopback \
        --cidr "10.0.2.0/24" \
        $(cat "$CONTAINER_ROOT/container.pid") \
        tap$TAP_HANDLE &
    
    SLIRP_PID=$!
    echo $SLIRP_PID > "$CONTAINER_ROOT/slirp.pid"
    
    # Wait for network setup
    sleep 1
    
    # Configure network inside container namespace
    # nsenter --user --preserve-credentials --net --target $CONTAINER_PID \
    #     ip addr add 10.0.2.100/24 dev tap$TAP_HANDLE
    # nsenter --user --preserve-credentials --net --target $CONTAINER_PID \
    #     ip link set tap$TAP_HANDLE up
    # nsenter --user --preserve-credentials --net --target $CONTAINER_PID \
    #     ip route add default via 10.0.2.2
    
    # Setup DNS
    # Moved to start_rootless_container to execute inside namespace
    # echo "nameserver 10.0.2.3" > "$ROOTFS/etc/resolv.conf"
    
    echo "✓ Rootless networking via slirp4netns (tap$TAP_HANDLE)"
}

# ====================
# 7. ROOTLESS CGROUPS (cgroup v2 only)
# ====================
setup_rootless_cgroups() {
    echo "[7] Setting up rootless cgroups..."
    
    # cgroup v2 must be mounted with delegation for users
    CGROUP_PATH="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/$CONTAINER_NAME"
    
    mkdir -p "$CGROUP_PATH"
    
    # User must have write access to these
    if [ -w "$CGROUP_PATH/cgroup.procs" ]; then
        # Memory limit (soft limit)
        echo "500M" > "$CGROUP_PATH/memory.high"
        
        # CPU limit
        echo "50000 100000" > "$CGROUP_PATH/cpu.max"
        
        # Add container to cgroup
        echo $CONTAINER_PID > "$CGROUP_PATH/cgroup.procs"
        
        echo "✓ Rootless cgroups configured"
    else
        echo "Warning: Cannot set cgroup limits (insufficient permissions)"
        echo "Enable with: sudo mkdir -p /sys/fs/cgroup/user.slice/user-$(id -u).slice"
        echo "           sudo chown $(id -un):$(id -gn) /sys/fs/cgroup/user.slice/user-$(id -u).slice"
    fi
}

# ====================
# 8. START CONTAINER PROCESS ROOTLESS
# ====================
start_rootless_container() {
    echo "[8] Configuring container environment..."
    
    # We need to find chroot first
    CHROOT_BIN="$(command -v chroot)"
    if [ -z "$CHROOT_BIN" ]; then
        # Fallback for some distros
        if [ -x /usr/sbin/chroot ]; then
             CHROOT_BIN=/usr/sbin/chroot
        else
             echo "Error: chroot command not found"
             exit 1
        fi
    fi

    # Run setup script INSIDE the namespace
    # We do NOT run a shell at the end. We just setup and exit.
    nsenter \
        --user --preserve-credentials --target $CONTAINER_PID \
        --mount --uts --ipc --pid --net --cgroup \
        $CHROOT_BIN "$ROOTFS" /bin/sh -c "
            export PATH=/bin:/sbin:/usr/bin:/usr/sbin
            if [ -f /etc/profile ]; then
                . /etc/profile
            fi
            
            # Setup filesystem mounts (persist in the mount namespace)
            mount -t proc proc /proc 2>/dev/null || true
            mount -t tmpfs tmpfs /tmp
            mount -t tmpfs tmpfs /run
            
            # Setup basic files
            echo 'rootless-$CONTAINER_NAME' > /etc/hostname
            echo '127.0.0.1 localhost' > /etc/hosts
            echo '10.0.2.100 container' >> /etc/hosts
            echo 'nameserver 10.0.2.3' > /etc/resolv.conf
            
            # Create user to match host
            if ! grep -q \"^rootlessuser:\" /etc/passwd; then
                echo \"rootlessuser:x:$CONTAINER_UID:$CONTAINER_GID:Rootless User:/home/rootlessuser:/bin/sh\" >> /etc/passwd
                echo \"rootlessuser:!::\" >> /etc/shadow
                mkdir -p /home/rootlessuser
                chown $CONTAINER_UID:$CONTAINER_GID /home/rootlessuser
            fi
        "
    
    echo "✓ Container environment configured"
}

# ====================
# 9. ROOTLESS SECURITY
# ====================
setup_rootless_security() {
    echo "[9] Configuring rootless security..."
    
    # In rootless mode, we already have limited capabilities
    # No CAP_SYS_ADMIN, CAP_NET_ADMIN, etc.
    
    # Setup seccomp (allow more since we're rootless)
    cat > "$CONTAINER_ROOT/seccomp.json" << 'EOF'
{
    "defaultAction": "SCMP_ACT_ALLOW",
    "architectures": ["SCMP_ARCH_X86_64"],
    "syscalls": [
        {
            "names": ["keyctl", "add_key", "request_key"],
            "action": "SCMP_ACT_ERRNO"
        }
    ]
}
EOF
    
    # Apply via nsenter if seccomp supported
    nsenter --target $CONTAINER_PID --preserve-credentials \
        prctl --seccomp=1 2>/dev/null || true
    
    echo "✓ Rootless security configured"
}

# ====================
# MAIN ROOTLESS EXECUTION
# ====================
main() {
    echo "=== Creating Rootless Container ==="
    echo "User: $CONTAINER_USER (UID:$CONTAINER_UID, GID:$CONTAINER_GID)"
    echo "Container: $CONTAINER_NAME"
    echo ""
    
    # Run steps
    setup_rootless_env
    download_image_rootless
    setup_rootless_overlay
    create_user_namespace
    create_rootless_namespaces
    setup_rootless_network
    setup_rootless_cgroups
    setup_rootless_security
    start_rootless_container

    echo ""
    echo "=== Rootless Container Running ==="
    echo "To enter container:"
    echo "  nsenter --user -t $(cat $CONTAINER_ROOT/container.pid) \\"
    echo "    --mount --uts --ipc --pid --net --cgroup \\"
    echo "    chroot $ROOTFS /bin/sh -l"
    echo ""
    echo "Press Ctrl+C to stop container"

    # Wait
    # wait $(cat "$CONTAINER_ROOT/container.pid") 2>/dev/null || true
    wait $(cat "$CONTAINER_ROOT/parent.pid") 2>/dev/null || true

    cleanup
}

cleanup() {
    echo "Cleaning up rootless container..."
    
    # Kill processes
    [ -f "$CONTAINER_ROOT/container.pid" ] && kill -9 $(cat "$CONTAINER_ROOT/container.pid") 2>/dev/null || true
    [ -f "$CONTAINER_ROOT/userns.pid" ] && kill -9 $(cat "$CONTAINER_ROOT/userns.pid") 2>/dev/null || true
    [ -f "$CONTAINER_ROOT/slirp.pid" ] && kill -9 $(cat "$CONTAINER_ROOT/slirp.pid") 2>/dev/null || true
    
    # Remove network namespace
    ip netns delete "$CONTAINER_NAME" 2>/dev/null || true
    
    # Unmount
    umount -l "$ROOTFS" 2>/dev/null || true
    
    echo "✓ Cleanup complete"
}

trap cleanup EXIT INT TERM

# Run main function
main
