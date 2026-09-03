#!/bin/bash

docker build -t legacy-app:test .

docker run -d --name legacy-test -p 5000:5000 legacy-app:test

for i in {1..5}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health)

    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "Container is healthy."
        break
    else
        echo "Health check attempt $i failed. Retrying..."

        if [ "$i" -eq 5 ]; then
            echo "Container failed to start."
            exit 1
        fi

        sleep 2
    fi
done

echo "Container healthy, starting endpoint tests."

./scripts/test-api.sh http://localhost:5000

docker stop legacy-test
docker rm legacy-test

echo "Test container stopped and removed."