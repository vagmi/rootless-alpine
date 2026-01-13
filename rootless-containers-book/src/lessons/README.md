# Lessons Learned

Building a container runtime from scratch is a humbling experience. Even with access to extensive documentation and powerful LLMs, the intricacies of Linux namespaces often lead to confusing dead ends.

What works in theory ("just map the UIDs!") often fails in practice due to the nuanced interplay between the kernel, the filesystem, and process hierarchy.

This chapter documents the specific "gotchas" I encountered. These aren't just bug fixes; they are lessons in how Linux actually works under the hood. I learned that **context is everything**: *where* you run a command (host vs. namespace) matters just as much as *what* command you run.
