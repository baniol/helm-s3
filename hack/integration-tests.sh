#!/usr/bin/env bash
set -euo pipefail
set -x

#
# Set up
#

# Prepare chart to play with.
helm fetch stable/postgresql --version 0.8.3

#
# Test: init repo
#

# Read region from AWS_DEFAULT_REGION environment variable

helm s3 init s3://test-bucket/charts
if [ $? -ne 0 ]; then
    echo "Failed to initialize repo"
    exit 1
fi

# Read region from parameter

helm s3 init --region us-east-1 s3://test-bucket/charts
if [ $? -ne 0 ]; then
    echo "Failed to initialize repo with specified"
    exit 1
fi

set +e # next command should return non-zero statu

helm s3 init --region eu-central-1 s3://test-bucket/charts
if [ $? -eq 0 ]; then
    echo "Repository cannot be initiated with incorrect region"
    exit 1
fi

set -e

mc ls helm-s3-minio/test-bucket/charts/index.yaml
if [ $? -ne 0 ]; then
    echo "Repository was not actually initialized"
    exit 1
fi

helm repo add test-repo s3://test-bucket/charts
if [ $? -ne 0 ]; then
    echo "Failed to add repo"
    exit 1
fi

#
# Test: push chart
#

helm s3 push postgresql-0.8.3.tgz test-repo
if [ $? -ne 0 ]; then
    echo "Failed to push chart to repo"
    exit 1
fi

mc ls helm-s3-minio/test-bucket/charts/postgresql-0.8.3.tgz
if [ $? -ne 0 ]; then
    echo "Chart was not actually uploaded"
    exit 1
fi

helm search test-repo/postgres | grep -q 0.8.3
if [ $? -ne 0 ]; then
    echo "Failed to find uploaded chart"
    exit 1
fi

#
# Test: push the same chart again
#

set +e # next command should return non-zero status

helm s3 push postgresql-0.8.3.tgz test-repo
if [ $? -eq 0 ]; then
    echo "The same chart must not be pushed again"
    exit 1
fi

set -e

helm s3 push --force postgresql-0.8.3.tgz test-repo
if [ $? -ne 0 ]; then
    echo "The same chart must be pushed again using --force"
    exit 1
fi

#
# Test: fetch chart
#

helm fetch test-repo/postgresql --version 0.8.3
if [ $? -ne 0 ]; then
    echo "Failed to fetch chart from repo"
    exit 1
fi

#
# Test: delete chart
#

helm s3 delete postgresql --version 0.8.3 test-repo
if [ $? -ne 0 ]; then
    echo "Failed to delete chart from repo"
    exit 1
fi

if mc ls -q helm-s3-minio/test-bucket/charts/postgresql-0.8.3.tgz 2>/dev/null ; then
    echo "Chart was not actually deleted"
    exit 1
fi

if helm search test-repo/postgres | grep -q 0.8.3 ; then
    echo "Failed to delete chart from index"
    exit 1
fi

#
# Test: push with content-type
#
expected_content_type='application/gzip'
helm s3 push --content-type=${expected_content_type} postgresql-0.8.3.tgz test-repo
if [ $? -ne 0 ]; then
    echo "Failed to push chart to repo"
    exit 1
fi

helm search test-repo/postgres | grep -q 0.8.3
if [ $? -ne 0 ]; then
    echo "Failed to find uploaded chart"
    exit 1
fi

mc ls helm-s3-minio/test-bucket/charts/postgresql-0.8.3.tgz
if [ $? -ne 0 ]; then
    echo "Chart was not actually uploaded"
    exit 1
fi

actual_content_type=$(mc stat helm-s3-minio/test-bucket/charts/postgresql-0.8.3.tgz | awk '/Content-Type/{print $NF}')
if [ $? -ne 0 ]; then
    echo "failed to stat uploaded chart"
    exit 1
fi

if [ "${expected_content_type}" != "${actual_content_type}" ]; then
    echo "content-type, expected '${expected_content_type}', actual '${actual_content_type}'"
    exit 1
fi

#
# Tear down
#

rm postgresql-0.8.3.tgz
helm repo remove test-repo
set +x

