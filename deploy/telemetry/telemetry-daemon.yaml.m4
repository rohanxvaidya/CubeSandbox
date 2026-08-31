---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: telemetry-daemon
  #namespace: rook-ceph 
  labels:
    app: telemetry-daemon
spec:
  selector:
    matchLabels:
      app: telemetry-daemon
  template:
    metadata:
      labels:
        app: telemetry-daemon
    spec:
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: telemetry-daemon
          #image: 10.67.115.219:5000/linux-telemetry:latest
          image: defn(`IMAGE')
          #command: ["/bin/bash"]
          #args: ["-m", "-c", "/usr/local/bin/toolbox.sh"]
ifelse("defn(`DEBUG_MODE')","3",`dnl
          command: ["sleep"]
          args: ["infinity"]
',)dnl
          imagePullPolicy: Always
          tty: true
          env:
            - name: MY_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: MY_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            # - name: ROOK_CEPH_USERNAME
            #   valueFrom:
            #     secretKeyRef:
            #       name: rook-ceph-mon
            #       key: ceph-username
            # - name: ROOK_CEPH_SECRET
            #   valueFrom:
            #     secretKeyRef:
            #       name: rook-ceph-mon
            #       key: ceph-secret
            - name: `CONFIGURATION_OPTIONS'
              value: "defn(`CONFIGURATION_OPTIONS')"
          securityContext:
            privileged: true
            runAsUser: 0
            capabilities:
              add:
                - ALL
          volumeMounts:
            - mountPath: /var
              name: var
            - mountPath: /sys
              name: sys
            - mountPath: /proc
              name: proc
            - mountPath: /dev
              name: dev
            - mountPath: /dev/shm
              name: devshm
            - mountPath: /sys/bus
              name: sysbus
            - mountPath: /lib/modules
              name: libmodules
            # - name: mon-endpoint-volume
            #   mountPath: /etc/rook
      hostNetwork: true
      volumes:
        - name: var
          hostPath:
            path: /var/
            type: Directory
        - name: sys
          hostPath:
            path: /sys
            type: Directory
        - name: proc
          hostPath:
            path: /proc
            type: Directory
        - name: dev
          hostPath:
            path: /dev
        - name: devshm
          hostPath:
            path: /dev/shm
            type: Directory
        - name: sysbus
          hostPath:
            path: /sys/bus
        - name: libmodules
          hostPath:
            path: /lib/modules
      affinity:
ifelse("defn(`NODE_AFFINITY')","1",`dnl
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: TELEMETRY_NODE
                operator: Exists
',)dnl
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - telemetry-daemon
            topologyKey: kubernetes.io/hostname
---
