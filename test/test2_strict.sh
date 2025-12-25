#!/bin/bash

#step1: 既存の正しい証明書でデータ通信ができることを確認
#step2: 不正な証明書を作成して適用するとadvertiseが拒否されることを確認

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

NODE_B=$(kubectl get pod -l app=node-b -o jsonpath="{.items[0].metadata.name}")
NODE_C=$(kubectl get pod -l app=node-c -o jsonpath="{.items[0].metadata.name}")

echo "Target Nodes: Node B ($NODE_B) -> Node C ($NODE_C)"
ORIG_ID=$(kubectl exec $NODE_B -- ndnsec get-default)

#step 1
echo -e "${GREEN}>>> [1] Testing communication with VALID certificate...${NC}"

echo -e "${GREEN}>>> [1-1] Creating sample file on Node B...${NC}"
kubectl exec $NODE_B -- bash -c "echo 'VALID_DATA_CONTENT_FROM_B' > /valid_sample.txt"

echo -e "${GREEN}>>> [1-2] Attempting 'nlsrc advertise' with bad key on Node B...${NC}"
if kubectl exec $NODE_B -- nlsrc advertise /test/valid-data > /dev/null 2>&1; then
    echo -e "${GREEN}[SUCCESS] Advertise command accepted (Normal operation).${NC}"
else
    echo -e "${RED}[FAIL] Advertise command rejected with valid key.${NC}"
    exit 1
fi

sleep 5

echo -e "${GREEN}>>> [1-3] Testing Data Plane (Node B -> Node C)...${NC}"
kubectl exec $NODE_B -- bash -c "ndnputchunks /test/valid-data < /valid_sample.txt" &
PID_PUT=$!
sleep 2

kubectl exec $NODE_C -- bash -c "ndncatchunks /test/valid-data"

if kubectl exec $NODE_C -- bash -c "ndncatchunks /test/valid-data 2>/dev/null" | grep -q "VALID_DATA_CONTENT_FROM_B"; then
    echo -e "${GREEN}[SUCCESS] Data verified!${NC}"
else
    echo -e "${RED}[FAIL] Data verification failed.${NC}"
    kill $PID_PUT 2>/dev/null
    exit 1
fi

echo -e "${GREEN}>>> [1-4] Cleaning up...${NC}"
kill $PID_PUT 2>/dev/null

#step 2
echo -e "${GREEN}>>> [2] Testing rejection with INVALID certificate...${NC}"
echo -e "${GREEN}>>> [2-1] Creating unauthorized identity on Node B...${NC}"
kubectl exec $NODE_B -- bash -c "ndnsec key-gen /bad/strict/identity | ndnsec cert-install -"

echo -e "${GREEN}>>> [2-2] Attempting 'nlsrc advertise' with BAD key...${NC}"
echo "Expectation: The command should FAIL."
kubectl exec $NODE_B -- nlsrc advertise /test/strict-data
if ! kubectl exec $NODE_B -- nlsrc advertise /test/strict-data > /tmp/strict_log 2>&1; then
    echo -e "${GREEN}[SUCCESS] Advertise command was REJECTED as expected.${NC}"
else
    echo -e "${RED}[FAIL] Advertise command was ACCEPTED unexpectedly! Security policy failed.${NC}"
    # 失敗時は不正identityを消して終了
    kubectl exec $NODE_B -- ndnsec delete /bad/strict/identity > /dev/null 2>&1
    exit 1
fi

echo -e "${GREEN}>>> [2-3] Cleaning up...${NC}"
kubectl exec $NODE_B -- ndnsec delete /bad/strict/identity > /dev/null 2>&1
kubectl exec $NODE_B -- rm /valid_sample.txt > /dev/null 2>&1
kubectl exec $NODE_B -- ndnsec set-default "$ORIG_ID"
echo "Done."
