# syntax = docker/dockerfile-upstream:master-labs
ARG BASE_IMAGE=alpine

FROM alpine:latest as nimbuilder

#RUN apt-get update && apt-get install -y curl xz-utils g++ git make
RUN apk update
RUN apk add curl xz g++ gcc make git vim perl linux-headers
ENV OPENSSLDIR=/usr/local/ssl

# Build OpenSSL 1 from source
RUN mkdir -p $OPENSSLDIR/src
WORKDIR $OPENSSLDIR/src
RUN git clone https://github.com/openssl/openssl.git --depth 1 -b OpenSSL_1_1_1-stable .
RUN ./config --prefix=$OPENSSLDIR --openssldir=$OPENSSLDIR
RUN make -j $(nproc)
RUN make -j $(nproc) install
RUN ls $OPENSSLDIR/*
ENV LD_LIBRARY_PATH="$OPENSSLDIR/lib:$LD_LIBRARY_PATH"
#RUN echo "$OPENSSLDIR/lib" > /etc/ld.so.conf.d/openssl.conf
#RUN ldconfig

WORKDIR /root/
RUN apk add bash gcompat parallel
#RUN curl https://nim-lang.org/choosenim/init.sh -sSf | bash -s -- -y
ENV PATH=/root/nim-1.6.10/bin:$PATH
RUN curl https://nim-lang.org/download/nim-1.6.10.tar.xz > nim-1.6.10.tar.xz && tar -Jxf nim-1.6.10.tar.xz
WORKDIR /root/nim-1.6.10
RUN for i in `seq 2`; do ./build.sh --parallel $(nproc); done ## i dont unsterstand why this stop-gap solution needed
RUN ./bin/nim c koch
RUN ./koch boot -d:release
RUN ./koch tools
WORKDIR /root/

FROM --platform=$BUILDPLATFORM goreleaser/goreleaser:latest as goreleaser
ADD . /app
WORKDIR /app
RUN goreleaser build --snapshot

FROM ${BASE_IMAGE}:latest as base
ENV OPENSSLDIR=/usr/local/ssl
COPY --from=nimbuilder /root/nim-1.6.10 /root/.nimble
COPY --from=nimbuilder $OPENSSLDIR $OPENSSLDIR
ENV PATH=/root/.nimble/bin:$PATH
RUN apk add --no-cache python3 py3-setuptools py3-virtualenv php nodejs npm make git gcompat


FROM base as actions
EXPOSE 3434
VOLUME /data
WORKDIR /data
ENV INITIAL_ADMIN_PASSWORD admin
ENV BIND 0.0.0.0:3434
ADD trusted-cgi /usr/bin/
ADD cgi-ctl /usr/bin/
ENTRYPOINT ["/usr/bin/trusted-cgi", "--disable-chroot"]

FROM base
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN printf "I'm building for TARGETPLATFORM=${TARGETPLATFORM}" \
    && printf ", TARGETARCH=${TARGETARCH}" \
    && printf ", TARGETVARIANT=${TARGETVARIANT} \n" \
    && printf "With uname -s : " && uname -s \
    && printf "and  uname -m : " && uname -mm
EXPOSE 3434
VOLUME /data
WORKDIR /data
ENV INITIAL_ADMIN_PASSWORD admin
ENV BIND 0.0.0.0:3434
COPY --from=goreleaser /app/dist/server_${TARGETOS}_${TARGETARCH}*${TARGETVARIANT}/trusted-cgi /usr/bin/
COPY --from=goreleaser /app/dist/client_${TARGETOS}_${TARGETARCH}*${TARGETVARIANT}/cgi-ctl /usr/bin/
ENTRYPOINT ["/usr/bin/trusted-cgi", "--disable-chroot"]
