# 0007: Software rendering only in v1

Date: 2026-10-31. Status: accepted.

## Context
macOS 27 offers VZCustomVirtioDevice; GPU acceleration for Linux guests is not provided by Apple. The only working evidence is vzgpu (0 stars, 10 days old, tearing and VMM aborts) and a blog post.

## Decision
No guest GPU in v1. Apps render with llvmpipe/pixman inside the guest. The compatibility system labels GPU-dependent apps honestly. This keeps one rendering path.

## Revisit when
A Venus/virgl path on macOS 27.x passes: Vulkan/GL clients render correctly in a window, no tearing at 60 fps, no VMM aborts in a 24 h soak.
