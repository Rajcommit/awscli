#!/bin/bash
set -euxo pipefail
curl -fsSL https://newerabucket2026.s3.us-east-1.amazonaws.com/userdataraw.sh -o /tmp/userdataraw.sh
bash /tmp/userdataraw.sh
