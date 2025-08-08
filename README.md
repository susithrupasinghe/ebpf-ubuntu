# eBPF Development Environment

This repository contains a Docker-based development environment for eBPF (Extended Berkeley Packet Filter) development and analysis. The image includes BCC (BPF Compiler Collection), bpftrace, bpftool, and various eBPF tools for system analysis and monitoring.

## Features

- **BCC (BPF Compiler Collection)** - Python and C++ APIs for eBPF
- **bpftrace** - High-level tracing language for eBPF
- **bpftool** - Command-line utility for eBPF operations
- **Pre-built eBPF tools** - 50+ ready-to-use eBPF tools for system analysis
- **Development tools** - vim, nano, git, curl, and other utilities

## Prerequisites

- Docker installed on your system
- Linux kernel with eBPF support (4.18+ recommended)
- Privileged access (for mounting bpffs and debugfs)

## Building the Image

### Option 1: Build Locally

```bash
# Clone this repository
git clone <repository-url>
cd ebpf

# Build the Docker image
docker build -t ebpf-ubuntu:bcc-src .
```

### Option 2: Use Pre-built Image from GitHub Container Registry

```bash
# Pull the latest image from GHCR
docker pull ghcr.io/YOUR_USERNAME/ebpf:main

# Or pull a specific branch
docker pull ghcr.io/YOUR_USERNAME/ebpf:develop
```

The build process includes:
1. Building BCC from source (v0.31.0)
2. Building bpftool from source
3. Installing runtime dependencies
4. Setting up example scripts

## Running the Container

### Docker Desktop Users (macOS/Windows)

**Important**: Docker Desktop uses LinuxKit kernel which doesn't have kernel headers available. BCC tools will not work, but bpftrace tools will.

```bash
# Basic run (bpftrace tools only)
docker run -it --rm --privileged \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  ebpf-ubuntu:bcc-src

# Test bpftrace tools (these work)
bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("exec pid=%d comm=%s\n", pid, comm); }'
```

### Linux Hosts

### Basic Usage

```bash
# Run with privileged access (required for eBPF functionality)
docker run -it --rm --privileged \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  ebpf-ubuntu:bcc-src
```

### Mount Points Explanation

- `--privileged`: Required for eBPF operations and mounting special filesystems
- `-v /sys/fs/bpf:/sys/fs/bpf`: Mounts the BPF filesystem
- `-v /sys/kernel/debug:/sys/kernel/debug`: Mounts debugfs for kernel debugging
- `-v /lib/modules:/lib/modules:ro`: Mounts host kernel headers (read-only)

### Alternative: Using Capabilities

If you prefer not to use `--privileged`, you can use specific capabilities:

```bash
docker run -it --rm \
  --cap-add=SYS_ADMIN \
  --cap-add=BPF \
  --cap-add=NET_ADMIN \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v /lib/modules:/lib/modules:ro \
  ebpf-ubuntu:bcc-src
```

## Initial Setup

Once inside the container, run the setup scripts to prepare the environment:

```bash
# Mount required filesystems
ebpf-ready.sh

# Setup kernel headers (if needed)
setup-kernel-headers.sh
```

These scripts will:
- Mount bpffs and debugfs if they're not already mounted
- Check for kernel headers and attempt to install them if missing

## Examples

### 1. Process Execution Monitoring

Monitor all process executions in real-time:

```bash
# Using bpftrace (included example)
python3 /opt/examples/execsnoop_bt.py

# Or run the bash version
/opt/examples/execsnoop_bt.sh

# Using BCC execsnoop tool
execsnoop-bpfcc
```

### 2. System Call Monitoring

Monitor system calls:

```bash
# Monitor all execve system calls
bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("exec pid=%d comm=%s\n", pid, comm); }'

# Monitor file opens
opensnoop-bpfcc

# Monitor network connections
tcpconnect-bpfcc
```

### 3. Performance Analysis

```bash
# CPU usage distribution
cpudist-bpfcc

# I/O latency analysis
biolatency-bpfcc

# Function call latency
funcslower-bpfcc
```

### 4. Network Analysis

```bash
# TCP connection tracking
tcpconnect-bpfcc

# TCP retransmissions
tcpretrans-bpfcc

# Network packet drops
tcpdrop-bpfcc
```

### 5. File System Monitoring

```bash
# File access patterns
filetop-bpfcc

# File life events
filelife-bpfcc

# VFS operations
vfsstat-bpfcc
```

## Available BCC Tools

The image includes 50+ pre-built eBPF tools. Here are some popular ones:

### Process Analysis
- `execsnoop-bpfcc` - Trace process execution
- `killsnoop-bpfcc` - Trace kill() syscalls
- `pidpersec-bpfcc` - Count new processes per second

### System Performance
- `cpudist-bpfcc` - CPU usage distribution
- `runqlat-bpfcc` - CPU run queue latency
- `runqlen-bpfcc` - CPU run queue length
- `offcputime-bpfcc` - Off-CPU time analysis

### I/O Analysis
- `biolatency-bpfcc` - Block I/O latency
- `biosnoop-bpfcc` - Block I/O events
- `biotop-bpfcc` - Top block I/O processes

### Network Analysis
- `tcpconnect-bpfcc` - TCP connections
- `tcpaccept-bpfcc` - TCP accepts
- `tcpretrans-bpfcc` - TCP retransmissions
- `tcpdrop-bpfcc` - TCP packet drops

### File System
- `filetop-bpfcc` - Top files by I/O
- `filelife-bpfcc` - File creation/deletion
- `vfsstat-bpfcc` - VFS statistics

## Development

### Python BCC Examples

```python
#!/usr/bin/env python3
from bcc import BPF

# Define eBPF program
bpf_text = """
int hello(void *ctx) {
    bpf_trace_printk("Hello, World!\\n");
    return 0;
}
"""

# Load and attach
b = BPF(text=bpf_text)
b.attach_kprobe(event="sys_clone", fn_name="hello")

# Print trace
b.trace_print()
```

### bpftrace Examples

```bash
# Simple hello world
bpftrace -e 'BEGIN { printf("Hello, World!\n"); }'

# Count syscalls
bpftrace -e 'tracepoint:syscalls:sys_enter_* { @[probe] = count(); }'

# Profile stack traces
bpftrace -e 'profile:hz:99 { @[kstack] = count(); }'
```

## Troubleshooting

### Common Issues

1. **Permission denied errors**
   - Ensure you're running with `--privileged` or appropriate capabilities
   - Check that bpffs and debugfs are mounted

2. **BCC tools not working (kernel headers missing)**
   - **Error**: `Unable to find kernel headers` or `chdir(/lib/modules/.../build): No such file or directory`
   - **Linux hosts**: Mount host kernel headers: `-v /lib/modules:/lib/modules:ro`
   - **Docker Desktop (macOS/Windows)**: LinuxKit kernel headers aren't available in packages
     - Use bpftrace tools instead (they don't require kernel headers)
     - Or use a Linux VM/remote host for full eBPF functionality
   - **Alternative**: Run `setup-kernel-headers.sh` inside the container for diagnostics

3. **Kernel version compatibility**
   - eBPF requires Linux kernel 4.18+ for full functionality
   - Some features require kernel 5.0+

4. **Missing symbols**
   - Some tools may require debug symbols (`linux-image-*-dbg` package)
   - Consider using a debug kernel for development

### Debugging

```bash
# Check eBPF support
cat /sys/kernel/debug/bpf/verifier_log

# Check available tracepoints
ls /sys/kernel/debug/tracing/events/

# Check BPF filesystem
ls /sys/fs/bpf/
```

## Resources

- [BCC Documentation](https://github.com/iovisor/bcc)
- [bpftrace Documentation](https://github.com/iovisor/bpftrace)
- [eBPF Documentation](https://ebpf.io/)
- [Linux Kernel eBPF](https://docs.kernel.org/bpf/)

## Development

### GitHub Actions

This repository includes GitHub Actions workflows for automated Docker image building:

- **`docker-build.yml`**: Advanced workflow with multiple tag strategies
- **`docker-build-simple.yml`**: Simple workflow that tags images with branch names

The workflows automatically:
- Build multi-platform images (amd64, arm64)
- Push to GitHub Container Registry (GHCR)
- Tag images with branch names (e.g., `main`, `develop`, `feature-xyz`)
- Cache layers for faster builds

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Push to your fork
5. Create a pull request

The workflow will automatically build and test your changes.

## License

This project is provided as-is for educational and development purposes.
