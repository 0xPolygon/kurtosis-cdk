FROM ghcr.io/0xpolygon/status-checker:v0.2.8
LABEL author="devtools@polygon.technology"
LABEL description="Helper image for offline status-checker environments"

COPY ./static_files/additional_services/status-checker-config/checks/ /opt/status-checker/checks/
# The binary is built to /usr/local/bin as kurtosis-cdk may overwrite the
# /opt/status-checker/checks/ directory.
RUN go build -o /usr/local/bin/decode-batch-l2-data /opt/status-checker/checks/l1-info-tree
