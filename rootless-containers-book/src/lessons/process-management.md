# Process Management & The Grandchild Problem

Shell scripting makes it easy to spawn background processes (`&`), but it makes tracking them surprisingly difficult.

## The Symptom
The container would start, print "Ready", and then immediately execute the cleanup function and die.

## The Code
I had a structure like this:

```bash
unshare --user --fork bash -c "
    unshare --mount --net --fork bash -c 'sleep infinity' &
    echo $! > container.pid
" &
# ...
wait $(cat container.pid)
```

## The "Wait" Limitation
The `wait` command in Bash has a strict rule: **You can only wait for your direct children.**

In my architecture:
1.  **Script (PID 100)** spawns ->
2.  **User NS `unshare` (PID 101)** spawns ->
3.  **Mount NS `unshare` (PID 102)** spawns ->
4.  **Container Payload (PID 103)**

I was trying to `wait 103` from PID 100.
The kernel immediately returns "not a child of this shell", so `wait` exits with code 0.
The script thinks "Oh, the container finished!", runs `cleanup()`, and kills everything.

## The Fix: Tracking the Parent
I realized I couldn't wait on the container process directly. I had to wait on the **User Namespace** process (PID 101), which is the direct child of my script.

I introduced `parent.pid` to track this intermediate process.

```bash
UNSHARE_PID=$!
echo $UNSHARE_PID > parent.pid
# ...
wait $(cat parent.pid)
```

This ensures the script stays alive as long as the namespace hierarchy exists.
