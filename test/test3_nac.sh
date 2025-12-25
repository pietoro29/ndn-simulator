#!/bin/bash

#Policy:
#   AM Node: node-b
#   Content Prefix: /ndn/jp/waseda/sim-site/node-b/homepage/index.html
#   Allowed Consumer: node-c
#   Denied Consumer: node-a

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

NODE_A=$(kubectl get pod -l app=node-a -o jsonpath="{.items[0].metadata.name}")
NODE_B=$(kubectl get pod -l app=node-b -o jsonpath="{.items[0].metadata.name}")
NODE_C=$(kubectl get pod -l app=node-c -o jsonpath="{.items[0].metadata.name}")

PREFIX="/ndn/jp/waseda/sim-site/node-b/homepage/index.html"
NAC_DIR="/root/nac"

echo "Target Nodes:"
echo "  AM/Producer: $NODE_B"
echo "  Allowed:     $NODE_C"
echo "  Denied:      $NODE_A"
echo "Prefix: $PREFIX"

echo -e "${GREEN}>>> [1] Starting KDK Server on Node B...${NC}"
kubectl exec $NODE_B -- bash -c "nohup $NAC_DIR/kdk-server > $NAC_DIR/kdk-server.log 2>&1 &"
sleep 2

echo -e "${GREEN}>>> [2] Starting Producer on Node B...${NC}"
kubectl exec $NODE_B -- bash -c "export NDN_DATA_PREFIX='$PREFIX'; nohup $NAC_DIR/producer > $NAC_DIR/producer.log 2>&1 &"
sleep 2

echo -e "${GREEN}>>> [3] Testing Allowed Consumer on Node C...${NC}"
kubectl exec $NODE_C -- bash -c "> $NAC_DIR/consumer.log"
kubectl exec $NODE_C -- bash -c "export NDN_DATA_PREFIX='$PREFIX'; nohup $NAC_DIR/consumer > $NAC_DIR/consumer.log 2>&1 &"
sleep 5

kubectl exec $NODE_C -- cat $NAC_DIR/consumer.log
LOG_C=$(kubectl exec $NODE_C -- cat $NAC_DIR/consumer.log)
if echo "$LOG_C" | grep -q "SUCCESS!"; then
    echo -e "${GREEN}[SUCCESS] Node C successfully accessed the content.${NC}"
else
    echo -e "${RED}[FAIL] Node C failed to access content.${NC}"
    exit 1
fi


echo -e "${GREEN}>>> [4] Testing Denied Consumer on Node A...${NC}"
kubectl exec $NODE_A -- bash -c "> $NAC_DIR/consumer.log"
kubectl exec $NODE_A -- bash -c "export NDN_DATA_PREFIX='$PREFIX'; nohup $NAC_DIR/consumer > $NAC_DIR/consumer.log 2>&1 &"
sleep 5

kubectl exec $NODE_A -- cat $NAC_DIR/consumer.log
LOG_A=$(kubectl exec $NODE_A -- cat $NAC_DIR/consumer.log)
if ! echo "$LOG_A" | grep -q "SUCCESS!"; then
    echo -e "${GREEN}[SUCCESS] Node A was DENIED access as expected.${NC}"
else
    echo -e "${RED}[FAIL] Node A successfully accessed content! (Security Breach)${NC}"
    exit 1
fi

echo -e "${GREEN}>>> [5] Test Complete. Cleaning up...${NC}"
for NODE in $NODE_A $NODE_B $NODE_C; do
    kubectl exec $NODE -- pkill -f "/root/nac" >/dev/null 2>&1
done
echo "Done."
