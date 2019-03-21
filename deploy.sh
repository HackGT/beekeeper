docker build -t hackgt/beekeeper:latest .
docker push hackgt/beekeeper:latest
kubectl --namespace=beekeeper set env deployment beekeeper-default --env="LAST_MANUAL_RESTART=$(date +%s)"