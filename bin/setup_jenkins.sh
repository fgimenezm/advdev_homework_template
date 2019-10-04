#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Set up Jenkins with sufficient resources
oc -n ${GUID}-jenkins new-app jenkins-persistent \
    --param ENABLE_OAUTH=true \
    --param MEMORY_LIMIT=4Gi \
    --param VOLUME_CAPACITY=4Gi \
    --param DISABLE_ADMINISTRATIVE_MONITORS=true

oc -n ${GUID}-jenkins set resources dc jenkins --limits=memory=4Gi,cpu=2 --requests=memory=2Gi,cpu=500m

# Create custom agent container image with skopeo
oc -n ${GUID}-jenkins new-build -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
    USER root\nRUN yum -y install skopeo && yum clean all\n
    USER 1001' --name=jenkins-agent-appdev

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
echo "apiVersion: v1
items:
- apiVersion: build.openshift.io/v1
  kind: BuildConfig
  metadata:
    name: tasks-pipeline
  spec:
    source:
      contextDir: openshift-tasks
      git:
        uri: $REPO
      type: Git
    strategy:
      jenkinsPipelineStrategy:
        env:
        - name: CLUSTER
          value: $CLUSTER
        - name: GUID
          value: $GUID
        - name: REPO
          value: $REPO
      type: JenkinsPipeline
kind: List" | oc -n ${GUID}-jenkins create -f - 

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done
