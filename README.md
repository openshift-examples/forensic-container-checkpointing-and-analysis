# Forensic container checkpointing and analysis

Technical notes for my "Forensic container checkpointing and analysis" at
<https://www.opensourcerers.org/>

Big applause 👏🏻 and thank you to [Adrian Reber](https://github.com/adrianreber) he did most of the work with previous blog posts:
 * <https://kubernetes.io/blog/2022/12/05/forensic-container-checkpointing-alpha/>
 * <https://kubernetes.io/blog/2023/03/10/forensic-container-analysis/>




## Requirements

An OpenShift 4.13 cluster with cluster-admin access

## Warning

You will lose the support status of your cluster, because we enabled not supported features.


## Enable ContainerCheckpoint

### Disable / pause MCP to rollout all changes at once

```bash
$ oc patch mcp/{master,worker} --type merge -p '{"spec":{"paused": false}}'
machineconfigpool.machineconfiguration.openshift.io/master patched
machineconfigpool.machineconfiguration.openshift.io/worker patched

```

### Enable featuregate: ContainerCheckpoint

via `oc edit`
```bash
$oc edit featuregate/cluster
```

And change/add
```yaml
spec:
  customNoUpgrade:
    enabled:
  	  - ContainerCheckpoint
  featureSet: CustomNoUpgrade
```

OR use `oc patch`

```bash

$ oc patch featuregate/cluster \
	--type='json' \
	--patch='[
    	{"op": "add", "path": "/spec/featureSet", "value": "CustomNoUpgrade"},
    	{"op": "add", "path": "/spec/customNoUpgrade", "value": {enabled: [ContainerCheckpoint]}}
	]'


```

### Enable CRIU in CRI-O

```bash
$ tee 05-worker-enable-criu.bu <<EOF
variant: openshift
version: 4.13.0
metadata:
  name: 05-worker-enable-criu
  labels:
	machineconfiguration.openshift.io/role: worker
storage:
  files:
  - path: /etc/crio/crio.conf.d/05-enable-criu
	mode: 0644
	overwrite: true
	contents:
  	inline: |
    	[crio.runtime]
    	enable_criu_support = true
EOF

$ butane  05-worker-enable-criu.bu -o 05-worker-enable-criu.yaml
 oc apply -f 05-worker-enable-criu.yaml
machineconfig.machineconfiguration.openshift.io/05-worker-enable-criu created
```

### Enable / Unpause MCP to rollout last two changes


```bash
$ oc patch mcp/{master,worker} --type merge -p '{"spec":{"paused": false}}'
machineconfigpool.machineconfiguration.openshift.io/master patched
machineconfigpool.machineconfiguration.openshift.io/worker patched

```

### Wait until MCP rollout is done

```bash
$ oc get mcp
...
```

## Deploy Demo application counters-app & fetch informations


```bash
# Create new project/namespace demo
oc new-project demo

oc apply -k https://github.com/openshift-examples/forensic-container-checkpointing-and-analysis/counters-app

# Get counter-app URL
export COUNTER_URL=$(oc get route/counters -o jsonpath="https://{.spec.host}")

# Get node where Pod is running
export NODE_NAME=$(oc get pods -l app=counters -o  jsonpath="{.items[0].spec.nodeName}" )

# Get pod name
export POD_NAME=$(oc get pods -l app=counters -o  jsonpath="{.items[0].metadata.name}" )


```

## Deploy checkpoint-analyser

```bash
# switch to same project as above - demo
oc project demo

oc apply -k https://github.com/openshift-examples/forensic-container-checkpointing-and-analysis/checkpoint-analyser

```

## Run queries against counters-app

```bash
$ curl ${COUNTER_URL}/create?test-file
counter: 0
$ curl ${COUNTER_URL}/secret?RANDOM_1432_KEY
counter: 1
$ curl ${COUNTER_URL}/
counter: 2
```

## Create checkpoint


```bash
$ export TOKEN=$(oc whoami -t )
$ curl -k -X POST --header "Authorization: Bearer $TOKEN"  https://api.demo.openshift.pub:6443/api/v1/nodes/$NODE_NAME/proxy/checkpoint/demo/$POD_NAME/counter
{"items":["/var/lib/kubelet/checkpoints/checkpoint-counters-857d7978fd-jnkck_demo-counter-2023-08-24T11:24:18Z.tar"]}
```


## Analyze checkpoint

### Get pod where the checkpoint is located

```bash
$ export CHECKPOINT_POD_NAME=$(oc get pods -l app.kubernetes.io/component=checkpoint-analyser -o jsonpath="{.items[?(@.spec.nodeName=='${NODE_NAME}')].metadata.name}")
```

### Use checkpoint analze pod

```bash
$ oc rsh $CHECKPOINT_POD_NAME
sh-5.2# cd /checkpoints/
sh-5.2# ls
checkpoint-counters-857d7978fd-jnkck_demo-counter-2023-08-24T11:24:18Z.tar
sh-5.2# checkpointctl show checkpoint-counters-857d7978fd-jnkck_demo-counter-2023-08-24T11\:24\:18Z.tar

Displaying container checkpoint data from checkpoint-counters-857d7978fd-jnkck_demo-counter-2023-08-24T11:24:18Z.tar

+-----------+--------------------------------------------------------------------------------------------+--------------+---------+--------------------------------+--------+-------------+------------+-------------------+
| CONTAINER |                                           IMAGE                                            |      ID      | RUNTIME |            CREATED             | ENGINE |     IP      | CHKPT SIZE | ROOT FS DIFF SIZE |
+-----------+--------------------------------------------------------------------------------------------+--------------+---------+--------------------------------+--------+-------------+------------+-------------------+
| counter   | quay.io/openshift-examples/forensic-container-checkpointing-and-analysis/counters-app:main | b7fe1c786b7d | runc    | 2023-08-24T11:19:38.607090024Z | CRI-O  | 10.130.2.99 | 8.7 MiB    | 3.0 KiB           |
+-----------+--------------------------------------------------------------------------------------------+--------------+---------+--------------------------------+--------+-------------+------------+-------------------+
sh-5.2# cd /tmp/
sh-5.2# mkdir checkpoint
sh-5.2# cd checkpoint/
sh-5.2# tar xf /checkpoints/checkpoint-counters-857d7978fd-jnkck_demo-counter-2023-08-24T11\:24\:18Z.tar
sh-5.2# ls
bind.mounts  checkpoint  config.dump  dump.log	io.kubernetes.cri-o.LogPath  rootfs-diff.tar  spec.dump  stats-dump
sh-5.2# sh-5.2# crit show checkpoint/pstree.img | jq .entries[].pid
1
sh-5.2# crit show checkpoint/core-1.img | jq .entries[0].tc.comm
"python3"
sh-5.2# ls  checkpoint/pages-*
checkpoint/pages-1.img
sh-5.2# grep -ao RANDOM_1432_KEY checkpoint/pages-*
RANDOM_1432_KEY
sh-5.2# tar xvf rootfs-diff.tar
app/test-file
sh-5.2# cd checkpoint/
sh-5.2# pwd
/tmp/checkpoint/checkpoint
sh-5.2# coredump-python3
sh-5.2# sh-5.2# echo info registers | gdb --core core.1 -q
BFD: warning: /tmp/checkpoint/checkpoint/core.1 has a segment extending past end of file

warning: malformed note - filename area is too big
[New LWP 1]
Missing separate debuginfo for the main executable file
Try: dnf --enablerepo='*debug*' install /usr/lib/debug/.build-id/3e/6eae34c82de9e112e48289c49532ee80ab3929

warning: Unexpected size of section `.reg-xstate/1' in core file.
Core was generated by `python3 counter.py'.

warning: Unexpected size of section `.reg-xstate/1' in core file.
#0  0x00007f563e142937 in ?? ()
(gdb) rax            0xfffffffffffffffc  -4
rbx            0x1f4               500
rcx            0x7f563e142937      140008385423671
rdx            0x1f4               500
rsi            0x1                 1
rdi            0x7f563de4c6b0      140008382318256
rbp            0x4345886f1693      0x4345886f1693
rsp            0x7ffd7fbf3a68      0x7ffd7fbf3a68
r8             0x0                 0
r9             0x0                 0
r10            0x4345518d0200      73965000000000
r11            0x246               582
r12            0x7f563e7741c0      140008391918016
r13            0x7f563df226c0      140008383194816
r14            0x7f563e72dbf8      140008391629816
r15            0x7f563dc8bfc0      140008380481472
rip            0x7f563e142937      0x7f563e142937
eflags         0x246               [ PF ZF IF ]
cs             0x33                51
ss             0x2b                43
ds             0x0                 0
es             0x0                 0
fs             0x0                 0
gs             0x0                 0
(gdb) sh-5.2#

```

### Copy checkpoint to your laptop for local analyze

```bash
$ oc cp $CHECKPOINT_POD_NAME:/checkpoints/checkpoint-counters-857d7978fd-jnkck_demo-counter-2023-08-24T11\:24\:18Z.tar checkpoint-counters.tar
```
