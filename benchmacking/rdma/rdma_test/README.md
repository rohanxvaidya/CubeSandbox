# RDMA Test Tool

A lightweight RDMA benchmark utility supporting:

- ping-pong latency test (`pingpong`)
- RDMA write bandwidth test (`write_bw`)
- server/client roles
- normal verbs mode and RDMA CM mode (`-R`)

## Build

On both nodes:

```bash
cd /home/mz/rdma/rdma_test
make
```

The binary is `./rdma_test_tool`.

## Dependencies

- `rdma-core` (headers and libs)
- build tools (`gcc`, `make`)

On Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y build-essential rdma-core libibverbs-dev librdmacm-dev
```

On openEuler/CentOS/RHEL:

```bash
sudo dnf install -y gcc make rdma-core rdma-core-devel libibverbs libibverbs-devel librdmacm librdmacm-devel
```

## Usage

### Server

```bash
./rdma_test_tool -s -a 192.168.0.2 -m pingpong -S 4096 -n 10000
```

### Client

```bash
./rdma_test_tool -c 192.168.0.2 -m pingpong -S 4096 -n 10000
```

### RDMA CM mode

Add `-R` on both sides:

```bash
# server
./rdma_test_tool -s -a 192.168.0.2 -m write_bw -S 4096 -n 100000 -R

# client
./rdma_test_tool -c 192.168.0.2 -m write_bw -S 4096 -n 100000 -R
```

### Run with script

```bash
# on client, need client node accessing server no with no password;
numactl -C 64 bash -x ./run_client_test.sh -c 192.168.0.3 --start-server --server-bind-ip 192.168.0.3 -m write_bw -S $((4*1024)) -n 600000000 -q 512 -Q 64 -l 16
```

## Key Parameters

- `-s`: run as server
- `-c <server_ip>`: run as client
- `-a <bind_ip>`: local bind IP (server)
- `-m <pingpong|write_bw>`: benchmark type
- `-S <size>`: IO size in bytes
- `-n <iters>`: iterations
- `-q <tx_depth>`: queue depth
- `-R`: use RDMA CM mode
- `-d <ib_device>`: IB device name (verbs mode)
- `-i <ib_port>`: IB port (verbs mode)
- `-g <gid_idx>`: GID index (verbs mode)

## Suggested Two-Node Run (your environment)

- Server node IP: `192.168.0.2`
- Client node IP: `192.168.0.3`
- Work dir on both: `/home/mz/rdma/rdma_test`

1. Start server on `192.168.0.2`
2. Run client on `192.168.0.3`
3. Record output latency/BW numbers from client side

## Notes

- Ensure RDMA link is up and both nodes can resolve route to each other on the RDMA network.
- If RoCE is used, set an appropriate `-g` in verbs mode.
