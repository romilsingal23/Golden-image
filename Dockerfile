FROM alpine:3.18 AS build

ARG PACKER_VERSION
ARG PACKER_VERSION_SHA256SUM

# Install wget and unzip
RUN apk add --no-cache wget unzip

# Download Packer
RUN wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip

# Verify the checksum and unzip Packer
RUN echo "${PACKER_VERSION_SHA256SUM}  packer_${PACKER_VERSION}_linux_amd64.zip" > checksum && sha256sum -c checksum
RUN unzip packer_${PACKER_VERSION}_linux_amd64.zip

FROM gcr.io/google.com/cloudsdktool/cloud-sdk:slim
RUN apt-get -y update && apt-get -y install ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build packer /usr/bin/packer
ENTRYPOINT ["/usr/bin/packer"]

