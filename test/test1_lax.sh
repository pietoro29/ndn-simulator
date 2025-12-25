#!/bin/bash

#期待: 証明書チェーン検証がないため、勝手な鍵でadvertiseでき、データ通信も成功する

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

NODE_B=$(kubectl get pod -l app=node-b -o jsonpath="{.items[0].metadata.name}")
NODE_C=$(kubectl get pod -l app=node-c -o jsonpath="{.items[0].metadata.name}")

echo "Target Nodes: Node B ($NODE_B) -> Node C ($NODE_C)"
echo -e "${GREEN}>>> [1] Creating unauthorized identity on Node B...${NC}"
# 不正な鍵を作成し、デフォルトに設定
kubectl exec $NODE_B -- bash -c "ndnsec key-gen /bad/lax/identity | ndnsec cert-install -"

echo -e "${GREEN}>>> [2] Creating sample file on Node B...${NC}"
# echoで/sample.txtにデータを書き込む
kubectl exec $NODE_B -- bash -c "echo 'LAX_DATA_CONTENT_FROM_B' > /sample.txt"

echo -e "${GREEN}>>> [3] Attempting 'nlsrc advertise' with bad key on Node B...${NC}"
if kubectl exec $NODE_B -- nlsrc advertise /test/lax-data > /dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS] Advertise command accepted (Expected for Lax).${NC}"
else
    echo -e "${RED}[FAIL] Advertise command rejected on Node B. Is this really Lax mode?${NC}"
    exit 1
fi

sleep 5

echo -e "${GREEN}>>> [4] Testing Data Plane (Node B -> Node C)...${NC}"
kubectl exec $NODE_B -- bash -c "ndnputchunks /test/lax-data < /sample.txt" &
PID_PUT=$!
sleep 2

#ndncatchunksでテキストファイルを受け取る
kubectl exec $NODE_C -- bash -c "ndncatchunks /test/lax-data"

if kubectl exec $NODE_C -- bash -c "ndncatchunks /test/lax-data 2>/dev/null" | grep -q "LAX_DATA_CONTENT_FROM_B"; then
    echo -e "${GREEN}[SUCCESS] Data verified!${NC}"
else
    echo -e "${RED}[FAIL] Data verification failed.${NC}"
    kill $PID_PUT 2>/dev/null
    exit 1
fi

echo -e "${GREEN}>>> [5] Cleaning up...${NC}"
kill $PID_PUT 2>/dev/null
kubectl exec $NODE_B -- ndnsec delete /bad/lax/identity > /dev/null 2>&1
kubectl exec $NODE_B -- rm /sample.txt > /dev/null 2>&1
echo "Done."
