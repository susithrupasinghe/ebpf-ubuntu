# ---------- Stage 1: build BCC from source ----------
    FROM ubuntu:24.04 AS bcc_builder
    ENV DEBIAN_FRONTEND=noninteractive
    
    # Build deps for BCC
    RUN apt-get update && apt-get install -y --no-install-recommends \
        git cmake build-essential \
        clang llvm llvm-dev libclang-dev \
        bison flex libelf-dev zlib1g-dev libedit-dev libcap-dev libdw-dev \
        libbpf-dev libzstd-dev python3 python3-pip python3-dev ca-certificates \
        zip \
     && rm -rf /var/lib/apt/lists/*
    
    ARG BCC_TAG=v0.31.0
    RUN git clone --depth=1 --branch ${BCC_TAG} https://github.com/iovisor/bcc.git /src/bcc
    
    # Configure BCC (no tests/man/examples)
    RUN cmake -S /src/bcc -B /build/bcc \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr \
          -DENABLE_LLVM_SHARED=ON \
          -DBUILD_TESTS=OFF \
          -DENABLE_MAN=OFF \
          -DENABLE_EXAMPLES=OFF \
          -DPYTHON_CMD=python3 \
          -DCMAKE_C_FLAGS="-Wno-error" \
          -DCMAKE_CXX_FLAGS="-Wno-error"
    
    # Build (single-thread to dodge rare race) and install
    RUN cmake --build /build/bcc -- -j1
    RUN cmake --install /build/bcc
    
    # Sanity: Python can import bcc (installed as a dist-egg by CMake)
    RUN python3 -c "import bcc, sys; print('bcc import ok; version:', getattr(bcc,'__version__','unknown'))"
    
    # Tools + symlinks
    RUN mkdir -p /opt/bcc-tools && cp -r /src/bcc/tools/* /opt/bcc-tools/
    RUN set -eux; cd /opt/bcc-tools; \
        for tool in \
          argsnoop bashreadline biolatency biosnoop biotop \
          cachestat cachetop cpudist cpuunclaimed dcsnoop dcstat execsnoop ext4dist \
          ext4slower filelife fileslower filetop funccount funcslower gethostlatency \
          hardirqs killsnoop mdflush mountsnoop naptime offcputime \
          oomkill opensnoop pidpersec profile runqlat runqlen runqslower \
          softirqs stackcount stats syncsnoop syscount tcpaccept tcpconnect tcpconnlat \
          tcpdrop tcplife tcpretrans tcprtt tcpsynbl tcpstates tcptop tcptracer \
          tcpsubnet tplist trace ttysnoop uobjnew vfsstat vfscount wakeuptime xfsdist xfsslower zfsdist \
        ; do \
          [ -f "${tool}.py" ] && ln -sf "/opt/bcc-tools/${tool}.py" "/usr/sbin/${tool}-bpfcc" || true; \
        done
    
    # ---------- Stage 2: build bpftool from source ----------
    FROM ubuntu:24.04 AS bpftool_builder
    ENV DEBIAN_FRONTEND=noninteractive
    RUN apt-get update && apt-get install -y --no-install-recommends \
        git make build-essential clang llvm pkg-config \
        libelf-dev zlib1g-dev libbpf-dev ca-certificates \
     && rm -rf /var/lib/apt/lists/*
    
    RUN git clone --recurse-submodules --depth=1 https://github.com/libbpf/bpftool /src/bpftool \
     || (git clone --depth=1 https://github.com/libbpf/bpftool /src/bpftool && \
         cd /src/bpftool && git submodule update --init --depth=1)
    
    RUN make -C /src/bpftool/src -j"$(nproc)"
    
    # ---------- Stage 3: runtime image ----------
    FROM ubuntu:24.04
    ENV DEBIAN_FRONTEND=noninteractive
    
    RUN apt-get update && apt-get install -y --no-install-recommends \
        vim nano less procps curl wget ca-certificates jq git make \
        clang llvm pkg-config libelf1 zlib1g libcap2 libedit2 libdw1 libzstd1 \
        libbpf1 iproute2 net-tools tcpdump strace python3 python3-pip bpftrace \
        kmod linux-headers-generic \
     && rm -rf /var/lib/apt/lists/*
    
    # Make "python" exist (some scripts still call it)
    RUN ln -sf /usr/bin/python3 /usr/bin/python
    
    # Bring in BCC + tools and bpftool binary
    COPY --from=bcc_builder /usr/ /usr/
    COPY --from=bcc_builder /opt/bcc-tools/ /opt/bcc-tools/
    COPY --from=bpftool_builder /src/bpftool/src/bpftool /usr/local/bin/bpftool
    
    # Helper to mount bpffs/debugfs inside container (needs caps/privs)
    RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'mount | grep -q " on /sys/fs/bpf type bpf " || mount -t bpf bpf /sys/fs/bpf 2>/dev/null || true' \
    'mount | grep -q " on /sys/kernel/debug type debugfs " || mount -t debugfs nodev /sys/kernel/debug 2>/dev/null || true' \
    'echo "[ok] bpffs/debugfs attempted (requires caps or --privileged)."' \
    > /usr/local/bin/ebpf-ready.sh && chmod +x /usr/local/bin/ebpf-ready.sh

    # Helper to setup kernel headers for eBPF tools
    RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'KERNEL_VERSION=$(uname -r)' \
    'HEADERS_DIR="/lib/modules/${KERNEL_VERSION}/build"' \
    'echo "[info] Kernel version: $KERNEL_VERSION"' \
    'if [ ! -d "$HEADERS_DIR" ]; then' \
    '  echo "[warn] Kernel headers not found at $HEADERS_DIR"' \
    '  if [[ "$KERNEL_VERSION" == *"linuxkit"* ]]; then' \
    '    echo "[info] Detected LinuxKit kernel - headers not available in packages"' \
    '    echo "[info] For Docker Desktop users: mount host headers with -v /lib/modules:/lib/modules:ro"' \
    '    echo "[info] For Linux hosts: install linux-headers-$(uname -r) package"' \
    '  else' \
    '    echo "[info] Trying to install kernel headers..."' \
    '    apt-get update && apt-get install -y linux-headers-generic || true' \
    '    if [ ! -d "$HEADERS_DIR" ]; then' \
    '      echo "[warn] Still no headers. Some eBPF tools may not work."' \
    '      echo "[info] You may need to mount host kernel headers or use a different kernel."' \
    '    else' \
    '      echo "[ok] Kernel headers found at $HEADERS_DIR"' \
    '    fi' \
    '  fi' \
    'else' \
    '  echo "[ok] Kernel headers found at $HEADERS_DIR"' \
    'fi' \
    > /usr/local/bin/setup-kernel-headers.sh && chmod +x /usr/local/bin/setup-kernel-headers.sh
    
    # Examples
    RUN mkdir -p /opt/examples
    
    # Bash example
    RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    'bpftrace -e "tracepoint:syscalls:sys_enter_execve { printf(\"exec pid=%d comm=%s\\n\", pid, comm); }"' \
    > /opt/examples/execsnoop_bt.sh && chmod +x /opt/examples/execsnoop_bt.sh

    # Python example (proper heredoc, no escaping hell)
    RUN cat <<'PY' >/opt/examples/execsnoop_bt.py
#!/usr/bin/env python3
import subprocess, time

prog = 'tracepoint:syscalls:sys_enter_execve { printf("exec pid=%d comm=%s\\n", pid, comm); }'
p = subprocess.Popen(["bpftrace", "-e", prog], stdout=subprocess.PIPE, text=True)
try:
    # generate a few execs so we see output
    for _ in range(3):
        subprocess.run(["/bin/ls"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.2)
    # print a handful of lines
    for _ in range(20):
        line = p.stdout.readline()
        if not line:
            break
        print(line.strip())
finally:
    p.terminate()
PY
    RUN chmod +x /opt/examples/execsnoop_bt.py

    
    WORKDIR /root
    CMD ["/bin/bash"]    