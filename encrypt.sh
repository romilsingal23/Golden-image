echo "Test data" > test.txt
gcloud kms encrypt \
    --key=rsingal_key \
    --keyring=rsingal-key-ring \
    --location=us-east1 \
    --plaintext-file=test.txt \
    --ciphertext-file=test.enc \
    --impersonate-service-account=rsingal-cloud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com
