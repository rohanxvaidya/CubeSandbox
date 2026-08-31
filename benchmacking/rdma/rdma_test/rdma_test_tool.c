#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <getopt.h>
#include <inttypes.h>
#include <infiniband/verbs.h>
#include <netdb.h>
#include <netinet/in.h>
#include <rdma/rdma_cma.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_PORT 18515
#define DEFAULT_SIZE 4096
#define DEFAULT_ITERS 1000
#define DEFAULT_TX_DEPTH 64
#define DEFAULT_CQ_MOD 64
#define DEFAULT_POST_LIST 1
#define DEFAULT_IB_PORT 1
#define DEFAULT_POLL_CQ_TIMEOUT_MS 10000
#define WRITE_BW_POLL_CQ_TIMEOUT_MS 60000
#define WRITE_BW_SERVER_MIN_TIMEOUT_MS 300000
#define WRITE_BW_PROGRESS_INTERVAL_NS 5000000000ull
#define MAX_POST_LIST 4096

/*
 * Simple RDMA benchmark tool.
 *
 * High-level flow:
 * 1. Parse CLI and choose pingpong or write_bw mode.
 * 2. Bring up an RC connection through either plain verbs + TCP sideband or
 *    the RDMA CM path.
 * 3. Register one local memory region and exchange its addr/rkey with peer.
 * 4. Run the benchmark loop:
 *    - pingpong uses SEND/RECV round trips to measure latency.
 *    - write_bw uses RDMA WRITE into peer memory and a final SEND marker.
 * 5. Tear down verbs / CM resources in reverse order.
 */

enum role {
    ROLE_SERVER = 0,
    ROLE_CLIENT = 1,
};

enum test_mode {
    MODE_PINGPONG = 0,
    MODE_WRITE_BW = 1,
};

struct options {
    enum role role;
    enum test_mode mode;
    const char *server_ip;
    const char *bind_ip;
    const char *dev_name;
    int port;
    int size;
    int iters;
    int tx_depth;
    int cq_mod;
    int post_list;
    int ib_port;
    int gid_idx;
    bool use_rdma_cm;
};

struct qp_info {
    uint16_t lid;
    uint32_t qpn;
    uint32_t psn;
    uint8_t gid[16];
};

struct mr_info {
    uint64_t addr;
    uint32_t rkey;
    uint32_t size;
};

struct rdma_ctx {
    struct options opt;

    /* TCP socket only used in plain verbs mode to exchange QP attributes. */
    int tcp_fd;

    struct rdma_event_channel *ec;
    struct rdma_cm_id *listener;
    struct rdma_cm_id *id;

    struct ibv_context *verbs;
    struct ibv_pd *pd;
    struct ibv_cq *cq;
    struct ibv_qp *qp;
    struct ibv_mr *mr;

    /* One registered allocation is split into RX and TX regions. */
    char *buf;
    size_t buf_len;
    char *recv_buf;
    char *send_buf;
    /* Local and peer memory metadata for RDMA WRITE target selection. */
    struct mr_info local_mr;
    struct mr_info remote_mr;
};

static volatile sig_atomic_t g_stop = 0;


//// 函数进入时调用
//void __cyg_profile_func_enter(void *func, void *caller) {
//    printf("enter: %p <- %p\n", func, caller);
//}
//
//// 函数退出时调用
//void __cyg_profile_func_exit(void *func, void *caller) {
//    printf("exit:  %p <- %p\n", func, caller);
//}



static void handle_stop_signal(int signo)
{
    (void)signo;
    g_stop = 1;
}

static void install_signal_handlers(void)
{
    struct sigaction sa;

    /* Let Ctrl+C / SIGTERM stop long or infinite runs cleanly. */
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_stop_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

/* Monotonic time is used for progress logging and throughput/latency math. */
static uint64_t now_ns(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t write_bw_server_timeout_ms(const struct rdma_ctx *ctx)
{
    double total_gbits;
    double estimated_ms;

    /*
     * Server only waits for the final SEND marker, so its timeout must cover
     * the full client-side transfer duration. Use a conservative 10 Gbps floor
     * plus extra slack so large iteration counts do not tear down the QP early.
     */
    total_gbits = ((double)ctx->opt.size * (double)ctx->opt.iters * 8.0) / 1e9;
    estimated_ms = (total_gbits / 10.0) * 1000.0 + 30000.0;

    if (estimated_ms < (double)WRITE_BW_SERVER_MIN_TIMEOUT_MS)
        return WRITE_BW_SERVER_MIN_TIMEOUT_MS;

    return (uint64_t)estimated_ms;
}

static void usage(const char *prog)
{
    fprintf(stderr,
            "Usage:\n"
            "  Server: %s -s [options]\n"
            "  Client: %s -c <server_ip> [options]\n\n"
            "Options:\n"
            "  -m <pingpong|write_bw>   Test mode (default: pingpong)\n"
            "  -s                       Run as server\n"
            "  -c <server_ip>           Run as client and connect to server IP\n"
            "  -a <bind_ip>             Local bind IP (default: 0.0.0.0)\n"
            "  -p <port>                Port (default: %d)\n"
            "  -S <size>                IO size in bytes (default: %d)\n"
            "  -n <iters>               Iterations; use 0 for infinite run (default: %d)\n"
            "  -q <tx_depth>            Tx depth (default: %d)\n"
            "  -Q <cq_mod>              Signal every N WRs in write_bw (default: %d)\n"
            "  -l <post_list>           WRs chained per post in write_bw (default: %d)\n"
            "  -d <ib_device>           IB device name (verbs mode only)\n"
            "  -i <ib_port>             IB port (verbs mode default: %d)\n"
            "  -g <gid_idx>             GID index (verbs mode, default: -1)\n"
            "  -R                       Use RDMA CM mode\n"
            "  -h                       Show this help\n",
            prog, prog, DEFAULT_PORT, DEFAULT_SIZE, DEFAULT_ITERS, DEFAULT_TX_DEPTH,
            DEFAULT_CQ_MOD, DEFAULT_POST_LIST, DEFAULT_IB_PORT);
}

static int parse_opts(int argc, char **argv, struct options *opt)
{
    int c;

    /* Seed every runtime option with a sensible default first. */
    memset(opt, 0, sizeof(*opt));
    opt->role = ROLE_SERVER;
    opt->mode = MODE_PINGPONG;
    opt->port = DEFAULT_PORT;
    opt->size = DEFAULT_SIZE;
    opt->iters = DEFAULT_ITERS;
    opt->tx_depth = DEFAULT_TX_DEPTH;
    opt->cq_mod = DEFAULT_CQ_MOD;
    opt->post_list = DEFAULT_POST_LIST;
    opt->ib_port = DEFAULT_IB_PORT;
    opt->gid_idx = -1;
    opt->bind_ip = "0.0.0.0";

    while ((c = getopt(argc, argv, "m:sc:a:p:S:n:q:Q:l:d:i:g:Rh")) != -1) {
        switch (c) {
        case 'm':
            if (strcmp(optarg, "pingpong") == 0) {
                opt->mode = MODE_PINGPONG;
            } else if (strcmp(optarg, "write_bw") == 0) {
                opt->mode = MODE_WRITE_BW;
            } else {
                fprintf(stderr, "Invalid mode: %s\n", optarg);
                return -1;
            }
            break;
        case 's':
            opt->role = ROLE_SERVER;
            break;
        case 'c':
            opt->role = ROLE_CLIENT;
            opt->server_ip = optarg;
            break;
        case 'a':
            opt->bind_ip = optarg;
            break;
        case 'p':
            opt->port = atoi(optarg);
            break;
        case 'S':
            opt->size = atoi(optarg);
            break;
        case 'n':
            opt->iters = atoi(optarg);
            break;
        case 'q':
            opt->tx_depth = atoi(optarg);
            break;
        case 'Q':
            opt->cq_mod = atoi(optarg);
            break;
        case 'l':
            opt->post_list = atoi(optarg);
            break;
        case 'd':
            opt->dev_name = optarg;
            break;
        case 'i':
            opt->ib_port = atoi(optarg);
            break;
        case 'g':
            opt->gid_idx = atoi(optarg);
            break;
        case 'R':
            opt->use_rdma_cm = true;
            break;
        case 'h':
            usage(argv[0]);
            exit(0);
        default:
            usage(argv[0]);
            return -1;
        }
    }

    /* Only the client needs a peer IP; the server just binds and listens. */
    if (opt->role == ROLE_CLIENT && !opt->server_ip) {
        fprintf(stderr, "Client mode requires -c <server_ip>\n");
        return -1;
    }

    /* Iterations may be zero now, which means run forever until signaled. */
    if (opt->size <= 0 || opt->iters < 0 || opt->port <= 0 ||
        opt->tx_depth <= 0 || opt->cq_mod <= 0 || opt->post_list <= 0 ||
        opt->post_list > MAX_POST_LIST) {
        fprintf(stderr, "Invalid numeric parameter\n");
        return -1;
    }

    return 0;
}

static int tcp_client_connect(const char *server_ip, int port)
{
    int fd;
    struct sockaddr_in addr;

    /* Plain verbs mode uses a small TCP socket only for QP attribute exchange. */
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, server_ip, &addr.sin_addr) != 1) {
        close(fd);
        return -1;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    return fd;
}

static int tcp_server_listen_accept(const char *bind_ip, int port)
{
    int lfd = -1;
    int cfd = -1;
    int one = 1;
    struct sockaddr_in addr;

    /* Create the temporary TCP listener used by the plain-verbs control path. */
    lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0)
        return -1;

    /* Allow fast restart of the helper socket between repeated test runs. */
    if (setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) < 0)
        goto out;

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, bind_ip, &addr.sin_addr) != 1)
        goto out;

    if (bind(lfd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
        goto out;

    if (listen(lfd, 1) < 0)
        goto out;

    /* Block until the peer connects and then return the accepted socket. */
    cfd = accept(lfd, NULL, NULL);

out:
    close(lfd);
    return cfd;
}

static int sock_xfer(int fd, void *tx, void *rx, size_t len)
{
    ssize_t n;
    size_t off = 0;

    /* Full-duplex control exchange: send local blob, then receive peer blob. */
    while (off < len) {
        n = send(fd, (char *)tx + off, len - off, 0);
        if (n <= 0)
            return -1;
        off += (size_t)n;
    }

    off = 0;
    while (off < len) {
        n = recv(fd, (char *)rx + off, len - off, MSG_WAITALL);
        if (n <= 0)
            return -1;
        off += (size_t)n;
    }

    return 0;
}

static struct ibv_device *pick_ib_device(const char *name)
{
    struct ibv_device **dev_list = NULL;
    struct ibv_device *ret = NULL;
    int num = 0;
    int i;

    /* Enumerate all verbs-capable HCAs visible on the host. */
    dev_list = ibv_get_device_list(&num);
    if (!dev_list || num == 0)
        return NULL;

    if (name) {
        for (i = 0; i < num; i++) {
            /* ibv_get_device_name lets the CLI choose a specific HCA. */
            if (strcmp(ibv_get_device_name(dev_list[i]), name) == 0) {
                ret = dev_list[i];
                break;
            }
        }
    } else {
        ret = dev_list[0];
    }

    if (ret) {
        struct ibv_device *chosen = ret;
        /* The chosen ibv_device remains valid after the list container is freed. */
        ibv_free_device_list(dev_list);
        return chosen;
    }

    /* Release the enumeration list in all paths to avoid a small libibverbs leak. */
    ibv_free_device_list(dev_list);
    return NULL;
}

/* Poll the CQ until a single completion arrives, then validate its status. */
static int poll_one_wc_timeout(struct ibv_cq *cq, struct ibv_wc *wc,
                               uint64_t timeout_ms)
{
    uint64_t start = now_ns();

    /* Busy-poll CQ until one completion arrives or timeout fires. */
    while (1) {
        /* ibv_poll_cq is the hot-path consumer for SEND/RECV/WRITE completions. */
        int n = ibv_poll_cq(cq, 1, wc);
        if (n < 0)
            return -1;
        if (n > 0) {
            if (wc->status != IBV_WC_SUCCESS) {
                fprintf(stderr,
                        "WC failed: status=%d(%s) opcode=%d vendor_err=%u\n",
                        wc->status, ibv_wc_status_str(wc->status), wc->opcode,
                        wc->vendor_err);
                return -1;
            }
            return 0;
        }
        if ((now_ns() - start) / 1000000ull > timeout_ms) {
            fprintf(stderr, "CQ poll timed out\n");
            return -1;
        }
    }
}

static int poll_one_wc(struct ibv_cq *cq, struct ibv_wc *wc)
{
    return poll_one_wc_timeout(cq, wc, DEFAULT_POLL_CQ_TIMEOUT_MS);
}

static int modify_qp_to_init(struct ibv_qp *qp, int ib_port)
{
    struct ibv_qp_attr attr;

    /* RC QP state machine: RESET -> INIT -> RTR -> RTS. */
    memset(&attr, 0, sizeof(attr));
    attr.qp_state = IBV_QPS_INIT;
    attr.pkey_index = 0;
    attr.port_num = (uint8_t)ib_port;
    attr.qp_access_flags = IBV_ACCESS_REMOTE_WRITE | IBV_ACCESS_LOCAL_WRITE;

    /* Move the RC QP into INIT so it can accept address and access settings. */
    return ibv_modify_qp(qp, &attr,
                         IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT |
                             IBV_QP_ACCESS_FLAGS);
}

/* Program the remote destination fields after the peer's QP info is known. */
static int modify_qp_to_rtr(struct ibv_qp *qp, const struct qp_info *remote,
                            int ib_port, int gid_idx)
{
    struct ibv_qp_attr attr;

    memset(&attr, 0, sizeof(attr));
    attr.qp_state = IBV_QPS_RTR;
    attr.path_mtu = IBV_MTU_1024;
    attr.dest_qp_num = remote->qpn;
    attr.rq_psn = remote->psn;
    attr.max_dest_rd_atomic = 1;
    attr.min_rnr_timer = 12;
    attr.ah_attr.is_global = (gid_idx >= 0) ? 1 : 0;
    attr.ah_attr.dlid = remote->lid;
    attr.ah_attr.sl = 0;
    attr.ah_attr.src_path_bits = 0;
    attr.ah_attr.port_num = (uint8_t)ib_port;

    /* For RoCE/global routing use GRH fields when gid_idx is provided. */
    if (gid_idx >= 0) {
        attr.ah_attr.grh.hop_limit = 1;
        attr.ah_attr.grh.dgid.global.interface_id =
            ((uint64_t *)remote->gid)[1];
        attr.ah_attr.grh.dgid.global.subnet_prefix =
            ((uint64_t *)remote->gid)[0];
        attr.ah_attr.grh.sgid_index = (uint8_t)gid_idx;
    }

    /* RTR arms the receive path with the peer QPN/PSN and address handle. */
    return ibv_modify_qp(qp, &attr,
                         IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
                             IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
                             IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER);
}

/* Finish the RC state machine so the send queue can issue work requests. */
static int modify_qp_to_rts(struct ibv_qp *qp, uint32_t psn)
{
    struct ibv_qp_attr attr;

    memset(&attr, 0, sizeof(attr));
    attr.qp_state = IBV_QPS_RTS;
    attr.timeout = 14;
    attr.retry_cnt = 7;
    attr.rnr_retry = 7;
    attr.sq_psn = psn;
    attr.max_rd_atomic = 1;

    /* RTS enables retries, timeout behavior, and the local SQ PSN. */
    return ibv_modify_qp(qp, &attr,
                         IBV_QP_STATE | IBV_QP_TIMEOUT | IBV_QP_RETRY_CNT |
                             IBV_QP_RNR_RETRY | IBV_QP_SQ_PSN |
                             IBV_QP_MAX_QP_RD_ATOMIC);
}

/* Post a RECV WR so the peer's SEND has a buffer to land in. */
static int post_recv_len(struct rdma_ctx *ctx, void *addr, size_t len)
{
    struct ibv_sge sge;
    struct ibv_recv_wr wr;
    struct ibv_recv_wr *bad;

    memset(&sge, 0, sizeof(sge));
    sge.addr = (uintptr_t)addr;
    sge.length = (uint32_t)len;
    sge.lkey = ctx->mr->lkey;

    /* Pre-post receive buffers to avoid RNR on incoming SEND traffic. */
    memset(&wr, 0, sizeof(wr));
    wr.wr_id = 1;
    wr.sg_list = &sge;
    wr.num_sge = 1;

    /* ibv_post_recv puts the WR on the RQ; completions arrive on the shared CQ. */
    return ibv_post_recv(ctx->qp, &wr, &bad);
}

static int post_recv(struct rdma_ctx *ctx)
{
    return post_recv_len(ctx, ctx->recv_buf, (size_t)ctx->opt.size);
}

static int post_send_len(struct rdma_ctx *ctx, void *addr, size_t len)
{
    struct ibv_sge sge;
    struct ibv_send_wr wr;
    struct ibv_send_wr *bad;

    memset(&sge, 0, sizeof(sge));
    sge.addr = (uintptr_t)addr;
    sge.length = (uint32_t)len;
    sge.lkey = ctx->mr->lkey;

    memset(&wr, 0, sizeof(wr));
    wr.wr_id = 2;
    wr.sg_list = &sge;
    wr.num_sge = 1;
    /* SEND is used as a small control channel (metadata and completion marker). */
    wr.opcode = IBV_WR_SEND;
    wr.send_flags = IBV_SEND_SIGNALED;

    /* ibv_post_send is also used for SEND operations, not only RDMA verbs. */
    return ibv_post_send(ctx->qp, &wr, &bad);
}

static int post_send(struct rdma_ctx *ctx)
{
    return post_send_len(ctx, ctx->send_buf, (size_t)ctx->opt.size);
}

static int post_write(struct rdma_ctx *ctx, bool signaled)
{
    struct ibv_sge sge;
    struct ibv_send_wr wr;
    struct ibv_send_wr *bad;

    memset(&sge, 0, sizeof(sge));
    sge.addr = (uintptr_t)ctx->send_buf;
    sge.length = (uint32_t)ctx->opt.size;
    sge.lkey = ctx->mr->lkey;

    memset(&wr, 0, sizeof(wr));
    wr.wr_id = 3;
    wr.sg_list = &sge;
    wr.num_sge = 1;
    /* RDMA WRITE copies local send_buf into peer remote_mr directly. */
    wr.opcode = IBV_WR_RDMA_WRITE;
    wr.send_flags = signaled ? IBV_SEND_SIGNALED : 0;
    wr.wr.rdma.remote_addr = ctx->remote_mr.addr;
    wr.wr.rdma.rkey = ctx->remote_mr.rkey;

    /* RDMA WRITE is submitted through ibv_post_send with opcode=IBV_WR_RDMA_WRITE. */
    return ibv_post_send(ctx->qp, &wr, &bad);
}

/* Build a linked list of WRITE WRs so one doorbell can submit multiple writes. */
static int post_write_chain(struct rdma_ctx *ctx, int wr_count, bool signal_last)
{
    struct ibv_sge sge[MAX_POST_LIST];
    struct ibv_send_wr wr[MAX_POST_LIST];
    struct ibv_send_wr *bad;
    int i;

    if (wr_count <= 0 || wr_count > MAX_POST_LIST)
        return -1;

    for (i = 0; i < wr_count; i++) {
        memset(&sge[i], 0, sizeof(sge[i]));
        sge[i].addr = (uintptr_t)ctx->send_buf;
        sge[i].length = (uint32_t)ctx->opt.size;
        sge[i].lkey = ctx->mr->lkey;

        memset(&wr[i], 0, sizeof(wr[i]));
        wr[i].wr_id = (uint64_t)(3 + i);
        wr[i].sg_list = &sge[i];
        wr[i].num_sge = 1;
        wr[i].opcode = IBV_WR_RDMA_WRITE;
        wr[i].send_flags = 0;
        wr[i].wr.rdma.remote_addr = ctx->remote_mr.addr;
        wr[i].wr.rdma.rkey = ctx->remote_mr.rkey;
        wr[i].next = (i == wr_count - 1) ? NULL : &wr[i + 1];
    }

    if (signal_last)
        wr[wr_count - 1].send_flags = IBV_SEND_SIGNALED;

    /* Posting the chain head submits the entire linked list to the send queue. */
    return ibv_post_send(ctx->qp, &wr[0], &bad);
}

/* Exchange each side's registered receive buffer addr/rkey over SEND/RECV. */
static int exchange_mr_via_send_recv(struct rdma_ctx *ctx)
{
    struct ibv_wc wc;
    char *recv_buf = ctx->recv_buf;
    char *send_buf = ctx->send_buf;

    if (ctx->buf_len < sizeof(struct mr_info) * 2) {
        fprintf(stderr, "Internal buffer too small for control exchange\n");
        return -1;
    }

    /*
     * Deterministic MR handshake:
     * client: RECV-post -> SEND local_mr -> wait 2 CQEs -> store remote_mr
     * server: RECV-post -> wait -> store remote_mr -> SEND local_mr -> wait
     */
    if (ctx->opt.role == ROLE_CLIENT) {
        memcpy(send_buf, &ctx->local_mr, sizeof(ctx->local_mr));
        if (post_recv_len(ctx, recv_buf, sizeof(ctx->remote_mr)))
            return -1;
        if (post_send_len(ctx, send_buf, sizeof(ctx->local_mr)))
            return -1;

        /* First CQE is SEND completion, second CQE is received peer metadata. */
        if (poll_one_wc(ctx->cq, &wc))
            return -1;
        if (poll_one_wc(ctx->cq, &wc))
            return -1;
        memcpy(&ctx->remote_mr, recv_buf, sizeof(ctx->remote_mr));
    } else {
        if (post_recv_len(ctx, recv_buf, sizeof(ctx->remote_mr)))
            return -1;
        if (poll_one_wc(ctx->cq, &wc))
            return -1;
        memcpy(&ctx->remote_mr, recv_buf, sizeof(ctx->remote_mr));

        memcpy(send_buf, &ctx->local_mr, sizeof(ctx->local_mr));
        if (post_send_len(ctx, send_buf, sizeof(ctx->local_mr)))
            return -1;
        if (poll_one_wc(ctx->cq, &wc))
            return -1;
    }

    return 0;
}

static int setup_resources_verbs(struct rdma_ctx *ctx)
{
    struct ibv_device *ib_dev;
    struct ibv_qp_init_attr qp_attr;
    size_t min_buf = sizeof(struct mr_info) * 2;
    size_t data_buf = (size_t)ctx->opt.size * 2;

    /* 1) Open device, 2) alloc PD, 3) create CQ, 4) create RC QP, 5) register MR. */
    ib_dev = pick_ib_device(ctx->opt.dev_name);
    if (!ib_dev) {
        fprintf(stderr, "No IB device found (or requested one not found)\n");
        return -1;
    }

    /* Open the HCA context selected from ibv_get_device_list. */
    ctx->verbs = ibv_open_device(ib_dev);
    if (!ctx->verbs)
        return -1;

    /* The protection domain scopes QP/MR objects that are allowed to interact. */
    ctx->pd = ibv_alloc_pd(ctx->verbs);
    if (!ctx->pd)
        return -1;

    /* One CQ is enough here because the benchmark serializes completion handling. */
    ctx->cq = ibv_create_cq(ctx->verbs, ctx->opt.tx_depth * 2 + 16, NULL, NULL, 0);
    if (!ctx->cq)
        return -1;

    memset(&qp_attr, 0, sizeof(qp_attr));
    qp_attr.send_cq = ctx->cq;
    qp_attr.recv_cq = ctx->cq;
    qp_attr.qp_type = IBV_QPT_RC;
    qp_attr.cap.max_send_wr = (uint32_t)(ctx->opt.tx_depth + 16);
    qp_attr.cap.max_recv_wr = (uint32_t)(ctx->opt.tx_depth + 16);
    qp_attr.cap.max_send_sge = 1;
    qp_attr.cap.max_recv_sge = 1;

    /* Create an RC QP manually in plain-verbs mode. */
    ctx->qp = ibv_create_qp(ctx->pd, &qp_attr);
    if (!ctx->qp)
        return -1;

    ctx->buf_len = data_buf > min_buf ? data_buf : min_buf;

    if (posix_memalign((void **)&ctx->buf, 4096, ctx->buf_len)) {
        return -1;
    }
    memset(ctx->buf, 0, ctx->buf_len);

    /* Register the whole local buffer once so SEND/RECV/WRITE can reference it by lkey/rkey. */
    ctx->mr = ibv_reg_mr(ctx->pd, ctx->buf, ctx->buf_len,
                         IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE);
    if (!ctx->mr)
        return -1;

    /* Keep RX/TX separated to avoid aliasing between posted RECV and SEND/WRITE payloads. */
    ctx->recv_buf = ctx->buf;
    ctx->send_buf = ctx->buf + ctx->opt.size;

    ctx->local_mr.addr = (uint64_t)(uintptr_t)ctx->recv_buf;
    ctx->local_mr.rkey = ctx->mr->rkey;
    ctx->local_mr.size = (uint32_t)ctx->opt.size;

    return 0;
}

static int verbs_connect_qp(struct rdma_ctx *ctx)
{
    struct ibv_port_attr port_attr;
    union ibv_gid gid;
    struct qp_info local, remote;
    uint32_t psn = (uint32_t)(lrand48() & 0xffffff);

    memset(&local, 0, sizeof(local));
    memset(&remote, 0, sizeof(remote));
    memset(&gid, 0, sizeof(gid));

    /* Query local port attributes to learn the LID used in plain IB mode. */
    if (ibv_query_port(ctx->verbs, (uint8_t)ctx->opt.ib_port, &port_attr))
        return -1;

    if (ctx->opt.gid_idx >= 0) {
        /* For RoCE, query the selected GID so the peer can route to us globally. */
        if (ibv_query_gid(ctx->verbs, (uint8_t)ctx->opt.ib_port,
                          ctx->opt.gid_idx, &gid)) {
            return -1;
        }
        memcpy(local.gid, &gid, 16);
    }

    local.lid = port_attr.lid;
    local.qpn = ctx->qp->qp_num;
    local.psn = psn;

    /* Exchange (lid,qpn,psn,gid) via TCP because plain verbs has no built-in CM. */
    if (ctx->opt.role == ROLE_SERVER) {
        ctx->tcp_fd = tcp_server_listen_accept(ctx->opt.bind_ip, ctx->opt.port);
    } else {
        ctx->tcp_fd = tcp_client_connect(ctx->opt.server_ip, ctx->opt.port);
    }
    if (ctx->tcp_fd < 0)
        return -1;

    if (sock_xfer(ctx->tcp_fd, &local, &remote, sizeof(local)))
        return -1;

    /* Drive QP state machine to RTS after peer attributes are known. */
    if (modify_qp_to_init(ctx->qp, ctx->opt.ib_port))
        return -1;
    if (modify_qp_to_rtr(ctx->qp, &remote, ctx->opt.ib_port, ctx->opt.gid_idx))
        return -1;
    if (modify_qp_to_rts(ctx->qp, psn))
        return -1;

    return 0;
}

static int wait_cm_event(struct rdma_event_channel *ec,
                         enum rdma_cm_event_type expected,
                         struct rdma_cm_event **out_ev)
{
    struct rdma_cm_event *ev = NULL;

    /* rdma_get_cm_event is the blocking receive side of the CM state machine. */
    if (rdma_get_cm_event(ec, &ev)) {
        perror("rdma_get_cm_event");
        return -1;
    }

    /* RDMA CM is event-driven; reject unexpected transitions early. */
    if (ev->event != expected) {
        fprintf(stderr, "Unexpected CM event: got %d expected %d\n", ev->event,
                expected);
        rdma_ack_cm_event(ev);
        return -1;
    }

    *out_ev = ev;
    return 0;
}

static int setup_resources_cm(struct rdma_ctx *ctx)
{
    struct ibv_qp_init_attr qp_attr;
    size_t min_buf = sizeof(struct mr_info) * 2;
    size_t data_buf = (size_t)ctx->opt.size * 2;

    /* In CM mode the id already owns the selected verbs context. */
    ctx->verbs = ctx->id->verbs;
    /* CM resolved the HCA already; from here resource setup looks like verbs mode. */
    ctx->pd = ibv_alloc_pd(ctx->verbs);
    if (!ctx->pd)
        return -1;

    ctx->cq = ibv_create_cq(ctx->verbs, ctx->opt.tx_depth * 2 + 16, NULL, NULL, 0);
    if (!ctx->cq)
        return -1;

    memset(&qp_attr, 0, sizeof(qp_attr));
    qp_attr.send_cq = ctx->cq;
    qp_attr.recv_cq = ctx->cq;
    qp_attr.qp_type = IBV_QPT_RC;
    qp_attr.cap.max_send_wr = (uint32_t)(ctx->opt.tx_depth + 16);
    qp_attr.cap.max_recv_wr = (uint32_t)(ctx->opt.tx_depth + 16);
    qp_attr.cap.max_send_sge = 1;
    qp_attr.cap.max_recv_sge = 1;

    /* CM path creates and binds QP through rdma_create_qp(id,...). */
    /* rdma_create_qp attaches the QP to the CM ID so CM can drive connection setup. */
    if (rdma_create_qp(ctx->id, ctx->pd, &qp_attr))
        return -1;

    ctx->qp = ctx->id->qp;

    ctx->buf_len = data_buf > min_buf ? data_buf : min_buf;

    if (posix_memalign((void **)&ctx->buf, 4096, ctx->buf_len)) {
        return -1;
    }
    memset(ctx->buf, 0, ctx->buf_len);

    ctx->mr = ibv_reg_mr(ctx->pd, ctx->buf, ctx->buf_len,
                         IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE);
    if (!ctx->mr)
        return -1;

    ctx->recv_buf = ctx->buf;
    ctx->send_buf = ctx->buf + ctx->opt.size;

    ctx->local_mr.addr = (uint64_t)(uintptr_t)ctx->recv_buf;
    ctx->local_mr.rkey = ctx->mr->rkey;
    ctx->local_mr.size = (uint32_t)ctx->opt.size;

    return 0;
}

static int cm_connect(struct rdma_ctx *ctx)
{
    struct rdma_cm_event *ev = NULL;
    struct rdma_conn_param conn_param;
    struct addrinfo *res = NULL;
    struct addrinfo hints;
    char port_str[16];

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_NUMERICSERV;
    snprintf(port_str, sizeof(port_str), "%d", ctx->opt.port);

    /* The event channel delivers address/route/connect lifecycle notifications. */
    ctx->ec = rdma_create_event_channel();
    if (!ctx->ec)
        return -1;

    /* CM flow:
     * server: create_id -> bind -> listen -> CONNECT_REQUEST -> accept -> ESTABLISHED
     * client: create_id -> resolve_addr -> resolve_route -> connect -> ESTABLISHED
     */
    if (ctx->opt.role == ROLE_SERVER) {
        if (getaddrinfo(ctx->opt.bind_ip, port_str, &hints, &res))
            return -1;

        /* Create a passive CM ID that will listen for incoming connection requests. */
        if (rdma_create_id(ctx->ec, &ctx->listener, NULL, RDMA_PS_TCP))
            return -1;
        /* Bind the passive CM ID to the requested local IP/port. */
        if (rdma_bind_addr(ctx->listener, res->ai_addr))
            return -1;
        /* Start the passive listen queue. */
        if (rdma_listen(ctx->listener, 1))
            return -1;

        if (wait_cm_event(ctx->ec, RDMA_CM_EVENT_CONNECT_REQUEST, &ev))
            return -1;
        ctx->id = ev->id;

        if (ev->param.conn.private_data_len == sizeof(struct mr_info) &&
            ev->param.conn.private_data) {
            memcpy(&ctx->remote_mr, ev->param.conn.private_data,
                   sizeof(struct mr_info));
        }
        rdma_ack_cm_event(ev);

        if (setup_resources_cm(ctx))
            return -1;

        /* Retry/rnr settings make CM startup more tolerant to timing races. */
        memset(&conn_param, 0, sizeof(conn_param));
        conn_param.private_data = &ctx->local_mr;
        conn_param.private_data_len = sizeof(ctx->local_mr);
        conn_param.initiator_depth = 1;
        conn_param.responder_resources = 1;
        conn_param.retry_count = 7;
        conn_param.rnr_retry_count = 7;

        /* Accept sends back our QP/MR state and transitions the connection forward. */
        if (rdma_accept(ctx->id, &conn_param))
            return -1;

        if (wait_cm_event(ctx->ec, RDMA_CM_EVENT_ESTABLISHED, &ev))
            return -1;
        rdma_ack_cm_event(ev);
    } else {
        if (getaddrinfo(ctx->opt.server_ip, port_str, &hints, &res))
            return -1;

        /* Create the active CM endpoint used by the client side. */
        if (rdma_create_id(ctx->ec, &ctx->id, NULL, RDMA_PS_TCP))
            return -1;

        /* Resolve destination IP to a local RDMA device and routeable path. */
        if (rdma_resolve_addr(ctx->id, NULL, res->ai_addr, 2000))
            return -1;
        if (wait_cm_event(ctx->ec, RDMA_CM_EVENT_ADDR_RESOLVED, &ev))
            return -1;
        rdma_ack_cm_event(ev);

        /* Resolve the path details after address resolution picks the device/port. */
        if (rdma_resolve_route(ctx->id, 2000))
            return -1;
        if (wait_cm_event(ctx->ec, RDMA_CM_EVENT_ROUTE_RESOLVED, &ev))
            return -1;
        rdma_ack_cm_event(ev);

        if (setup_resources_cm(ctx))
            return -1;

        memset(&conn_param, 0, sizeof(conn_param));
        conn_param.private_data = &ctx->local_mr;
        conn_param.private_data_len = sizeof(ctx->local_mr);
        conn_param.initiator_depth = 1;
        conn_param.responder_resources = 1;
        conn_param.retry_count = 7;
        conn_param.rnr_retry_count = 7;

        /* Active connect sends our private data and asks the peer to establish QPs. */
        if (rdma_connect(ctx->id, &conn_param))
            return -1;

        if (wait_cm_event(ctx->ec, RDMA_CM_EVENT_ESTABLISHED, &ev))
            return -1;

        if (ev->param.conn.private_data_len == sizeof(struct mr_info) &&
            ev->param.conn.private_data) {
            memcpy(&ctx->remote_mr, ev->param.conn.private_data,
                   sizeof(struct mr_info));
        }
        rdma_ack_cm_event(ev);
    }

    if (res)
        freeaddrinfo(res);

    return 0;
}

static int do_pingpong(struct rdma_ctx *ctx)
{
    uint64_t iters_done = 0;
    struct ibv_wc wc;
    uint64_t start, end, progress_deadline;
    bool infinite = (ctx->opt.iters == 0);

    /* pingpong: one SEND request + one SEND response per iteration. */
    if (ctx->opt.role == ROLE_SERVER) {
        start = now_ns();
        progress_deadline = start + WRITE_BW_PROGRESS_INTERVAL_NS;
        while (!g_stop && (infinite || iters_done < (uint64_t)ctx->opt.iters)) {
            if (post_recv(ctx))
                return -1;
            if (poll_one_wc(ctx->cq, &wc))
                return -1;
            if (post_send(ctx))
                return -1;
            if (poll_one_wc(ctx->cq, &wc))
                return -1;

            iters_done++;
            if (infinite && now_ns() >= progress_deadline) {
                fprintf(stderr, "pingpong server progress: iters=%" PRIu64 "\n",
                        iters_done);
                progress_deadline = now_ns() + WRITE_BW_PROGRESS_INTERVAL_NS;
            }
        }
        if (infinite && g_stop)
            printf("pingpong server stopped after %" PRIu64 " iterations\n", iters_done);
        else
            printf("pingpong server completed %" PRIu64 " iterations\n", iters_done);
        return 0;
    }

    /* Client measures RTT over the full request/response loop. */
    start = now_ns();
    progress_deadline = start + WRITE_BW_PROGRESS_INTERVAL_NS;
    while (!g_stop && (infinite || iters_done < (uint64_t)ctx->opt.iters)) {
        if (post_recv(ctx))
            return -1;
        if (post_send(ctx))
            return -1;
        if (poll_one_wc(ctx->cq, &wc))
            return -1;
        if (poll_one_wc(ctx->cq, &wc))
            return -1;

        iters_done++;
        if (infinite && now_ns() >= progress_deadline) {
            double elapsed_sec = (double)(now_ns() - start) / 1000000000.0;
            double rtt_us = ((elapsed_sec * 1e6) / (double)iters_done);
            fprintf(stderr,
                    "pingpong progress: iters=%" PRIu64 " avg_rtt=%.3f us\n",
                    iters_done, rtt_us);
            progress_deadline = now_ns() + WRITE_BW_PROGRESS_INTERVAL_NS;
        }
    }
    end = now_ns();

    if (iters_done > 0) {
        double total_us = (double)(end - start) / 1000.0;
        double rtt_us = total_us / (double)iters_done;
        double one_way_us = rtt_us / 2.0;
        printf("pingpong result: iters=%" PRIu64 " size=%d RTT=%.3f us one-way=%.3f us\n",
               iters_done, ctx->opt.size, rtt_us, one_way_us);
    } else if (g_stop) {
        printf("pingpong stopped before any completed iteration\n");
    }

    return 0;
}

static int do_write_bw(struct rdma_ctx *ctx)
{
    int batch;
    int remaining;
    int can_post;
    uint64_t posted = 0;
    uint64_t inflight = 0;
    uint64_t unsignaled_run = 0;
    bool infinite = (ctx->opt.iters == 0);
    int effective_cq_mod;
    uint64_t poll_timeout_ms = WRITE_BW_POLL_CQ_TIMEOUT_MS;
    uint64_t progress_deadline;
    struct ibv_wc wc;
    uint64_t start, end;

    /* Server is passive target; one final SEND marker ends the finite run. */
    if (ctx->opt.role == ROLE_SERVER) {
        if (infinite) {
            fprintf(stderr, "write_bw server running in infinite mode (Ctrl+C to stop)\n");
            /* Infinite write_bw server does not need CQ traffic; just stay alive. */
            while (!g_stop)
                sleep(1);
            return 0;
        }

        poll_timeout_ms = write_bw_server_timeout_ms(ctx);
        if (post_recv(ctx))
            return -1;
        if (poll_one_wc_timeout(ctx->cq, &wc, poll_timeout_ms))
            return -1;
        printf("write_bw server observed completion marker\n");
        return 0;
    }

    memset(ctx->send_buf, 0x5a, (size_t)ctx->opt.size);

    /* Client drives the write stream and computes throughput from elapsed time. */
    /*
     * Throughput mode:
     * - keep a window of WRs in flight (bounded by tx_depth)
     * - signal only every N WRs (cq_mod) to reduce CQE overhead
     */
    effective_cq_mod = ctx->opt.cq_mod;
    if (effective_cq_mod > ctx->opt.tx_depth)
        effective_cq_mod = ctx->opt.tx_depth;

    start = now_ns();
    progress_deadline = start + WRITE_BW_PROGRESS_INTERVAL_NS;
    while (!g_stop && (infinite || posted < (uint64_t)ctx->opt.iters)) {
        bool signaled;

        if (inflight >= (uint64_t)ctx->opt.tx_depth)
            can_post = 0;
        else
            can_post = ctx->opt.tx_depth - (int)inflight;

        /* When the SQ window is full, wait for a signaled completion to free space. */
        if (can_post <= 0) {
            if (poll_one_wc_timeout(ctx->cq, &wc, poll_timeout_ms))
                return -1;
            inflight -= unsignaled_run;
            unsignaled_run = 0;
            continue;
        }

        remaining = infinite ? ctx->opt.tx_depth : (int)((uint64_t)ctx->opt.iters - posted);
        batch = ctx->opt.post_list;
        if (batch > remaining)
            batch = remaining;
        if (batch > can_post)
            batch = can_post;

        signaled = (unsignaled_run + (uint64_t)batch >= (uint64_t)effective_cq_mod) ||
                   (!infinite && posted + (uint64_t)batch == (uint64_t)ctx->opt.iters);

        /* Submit either one WRITE or a chained burst of WRITEs per doorbell. */
        if (batch == 1) {
            if (post_write(ctx, signaled))
                return -1;
        } else {
            if (post_write_chain(ctx, batch, signaled))
                return -1;
        }

        posted += batch;
        inflight += batch;
        unsignaled_run += batch;

        if (signaled) {
            if (poll_one_wc_timeout(ctx->cq, &wc, poll_timeout_ms))
                return -1;
            inflight -= unsignaled_run;
            unsignaled_run = 0;
        }

        if ((infinite || (uint64_t)ctx->opt.iters >= 10000000) &&
            now_ns() >= progress_deadline) {
            double elapsed_sec = (double)(now_ns() - start) / 1000000000.0;
            double bytes_done = (double)ctx->opt.size * (double)posted;
            double gbps = (bytes_done * 8.0) / elapsed_sec / 1e9;

            if (infinite) {
                fprintf(stderr,
                        "write_bw progress: posted=%" PRIu64 " inflight=%" PRIu64 " BW=%.3f Gbps\n",
                        posted, inflight, gbps);
            } else {
                fprintf(stderr,
                        "write_bw progress: posted=%" PRIu64 "/%d inflight=%" PRIu64 " BW=%.3f Gbps\n",
                        posted, ctx->opt.iters, inflight, gbps);
            }
            progress_deadline = now_ns() + WRITE_BW_PROGRESS_INTERVAL_NS;
        }
    }
    end = now_ns();

    if (infinite) {
        if (posted > 0) {
            double sec = (double)(end - start) / 1000000000.0;
            double bytes = (double)ctx->opt.size * (double)posted;
            double gbps = (bytes * 8.0) / sec / 1e9;
            double gibps = bytes / sec / (1024.0 * 1024.0 * 1024.0);
            printf("write_bw stopped: posted=%" PRIu64 " size=%d BW=%.3f Gbps (%.3f GiB/s)\n",
                   posted, ctx->opt.size, gbps, gibps);
        } else {
            printf("write_bw stopped before posting any WR\n");
        }
        return 0;
    }

    /* SEND a final marker so the passive server knows the finite test is done. */
    if (post_send(ctx))
        return -1;
    if (poll_one_wc_timeout(ctx->cq, &wc, poll_timeout_ms))
        return -1;

    {
        double sec = (double)(end - start) / 1000000000.0;
        double bytes = (double)ctx->opt.size * (double)posted;
        double gbps = (bytes * 8.0) / sec / 1e9;
        double gibps = bytes / sec / (1024.0 * 1024.0 * 1024.0);
        printf("write_bw result: iters=%" PRIu64 " size=%d BW=%.3f Gbps (%.3f GiB/s)\n",
               posted, ctx->opt.size, gbps, gibps);
    }

    return 0;
}

static void cleanup(struct rdma_ctx *ctx)
{
    /* Destroy in reverse dependency order. */
    /* Deregister the MR before destroying the PD it belongs to. */
    if (ctx->mr)
        ibv_dereg_mr(ctx->mr);
    /* Plain-verbs QPs are owned directly by us; CM-owned QPs die with the CM ID. */
    if (ctx->qp && !ctx->opt.use_rdma_cm)
        ibv_destroy_qp(ctx->qp);
    if (ctx->cq)
        ibv_destroy_cq(ctx->cq);
    if (ctx->pd)
        ibv_dealloc_pd(ctx->pd);
    if (ctx->buf)
        free(ctx->buf);

    if (ctx->opt.use_rdma_cm) {
        /* CM teardown releases the connection endpoint and any associated QP. */
        if (ctx->id)
            rdma_destroy_id(ctx->id);
        if (ctx->listener)
            rdma_destroy_id(ctx->listener);
        if (ctx->ec)
            rdma_destroy_event_channel(ctx->ec);
    } else {
        /* In verbs mode we close the HCA context explicitly. */
        if (ctx->verbs)
            ibv_close_device(ctx->verbs);
        if (ctx->tcp_fd >= 0)
            close(ctx->tcp_fd);
    }
}

int main(int argc, char **argv)
{
    struct rdma_ctx ctx;
    int rc;

    /* One context object owns the entire lifetime of transport, memory, and test state. */
    memset(&ctx, 0, sizeof(ctx));
    ctx.tcp_fd = -1;

    /* Parse the CLI before allocating any RDMA resources. */
    if (parse_opts(argc, argv, &ctx.opt))
        return 1;

    install_signal_handlers();

    srand48((long)time(NULL));

    /* Step 1: establish transport path (CM or plain verbs + TCP sideband). */
    if (ctx.opt.use_rdma_cm) {
        rc = cm_connect(&ctx);
    } else {
        /* Plain verbs path requires both local resource creation and TCP sideband exchange. */
        rc = setup_resources_verbs(&ctx);
        if (!rc)
            rc = verbs_connect_qp(&ctx);
    }

    if (rc) {
        fprintf(stderr, "Connection setup failed\n");
        cleanup(&ctx);
        return 1;
    }

    /* Step 2: exchange memory metadata so WRITE can target peer memory. */
    if (exchange_mr_via_send_recv(&ctx)) {
        fprintf(stderr, "MR exchange failed\n");
        cleanup(&ctx);
        return 1;
    }

    /* Step 3: run selected benchmark loop. */
    if (ctx.opt.mode == MODE_PINGPONG)
        rc = do_pingpong(&ctx);
    else
        rc = do_write_bw(&ctx);

    cleanup(&ctx);
    return rc ? 1 : 0;
}
