#!/bin/sh

#----------------------------
# build and package lambda
#----------------------------

cd src/
rm -rf .serverless/
sls package --name lambda_function_payload
rm ../lets-encrypt-renew-certificates.zip
mv .serverless/lets-encrypt-renew-certificates.zip ../
rm -rf .serverless/
