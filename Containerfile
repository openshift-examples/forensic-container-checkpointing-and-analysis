FROM  quay.io/fedora/fedora:38

WORKDIR /opt/

RUN curl -L -O http://github.com/checkpoint-restore/criu/archive/v3.18/criu-3.18.tar.gz \
 && tar xzvf criu-3.18.tar.gz \
 && cd criu-3.18 \
 && sh scripts/ci/prepare-for-fedora-rawhide.sh \
 && make \
 # All because of /opt/criu-3.18/coredump/coredump-python3
 && dnf install -y coreutils-single --allowerasing \
 && ln -s /usr/lib64/libtinfo.so.6.4 /usr/lib64/libtinfo.so.6.2 \
 && ln -s /usr/lib64/liblzma.so.5 /usr/lib64/liblzma.so.5.2.5 \
 && ln -s /usr/lib64/libssl.so.3 /usr/lib64/libssl.so.3.0.1 \
 && ln -s /usr/lib64/libz.so.1 /usr/lib64/libz.so.1.2.11 \
 && ln -s /usr/lib64/libcrypto.so.3.0.9 /usr/lib64/libcrypto.so.3.0.1 \
 && ln -s /usr/lib64/libpcre2-8.so.0 /usr/lib64/libpcre2-8.so.0.11.0 \
 # Cleanup to shrink layer size and remove useless data
 && dnf clean all && rm -rf /var/cache/yum


ENV PATH="/opt/criu-3.18/coredump/:/opt/criu-3.18/crit/:$PATH"

RUN dnf install -y gdb python3.9 \
    golang && dnf clean all && rm -rf /var/cache/yum

# Install debug info for gdb example
RUN dnf --enablerepo='*debug*' install -y \
    python3.9-debuginfo bash-debuginfo coreutils-debuginfo \
 && dnf clean all && rm -rf /var/cache/yum



RUN git clone https://github.com/checkpoint-restore/checkpointctl.git \
 && cd checkpointctl \
 && make install \
 && rm -rf /opt/checkpointctl

# RUN git clone -b v6.3.0 https://github.com/checkpoint-restore/go-criu.git \
#  && cd go-criu \
#  && make \
#  && cp -v crit/bin/crit /usr/local/bin \
#  && rm -rf /opt/go-criu*


