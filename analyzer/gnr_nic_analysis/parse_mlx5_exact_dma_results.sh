#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <capture_dir>" >&2
    echo "Example: $0 /home/mz/gnr_nic_perf/260408/mlx5_exact_dma_forced2" >&2
    exit 1
fi

CAP_DIR="$1"
FILTERED_LOG="${CAP_DIR}/mlx5_exact_dma_filtered.log"
OUT_SUMMARY="${CAP_DIR}/summary_queue_ring_and_dma.txt"
OUT_QUEUE="${CAP_DIR}/summary_queue_ring.csv"
OUT_PDEV_DMA="${CAP_DIR}/summary_pdev_dma.txt"
OUT_DMA_RATE="${CAP_DIR}/summary_dma_rate_per_sec.txt"

if [[ ! -r "$FILTERED_LOG" ]]; then
    echo "Missing input: $FILTERED_LOG" >&2
    exit 1
fi

awk -v out_queue="$OUT_QUEUE" -v out_pdev="$OUT_PDEV_DMA" -v out_rate="$OUT_DMA_RATE" -v out_summary="$OUT_SUMMARY" '
BEGIN {
    FS=" ";
    OFS=",";
}

function kv(line, key,    m) {
    if (match(line, key "=([^ ]+)", m)) {
        return m[1];
    }
    return "";
}

{
    line = $0;
    type = $1;

    if (type == "SQ_OPEN" || type == "SQ_CUR") {
        pdev = kv(line, "pdev");
        ch_ix = kv(line, "ch_ix");
        txq_ix = kv(line, "txq_ix");
        sqn = kv(line, "sqn");
        db_dma = kv(line, "db_dma");
        npages = kv(line, "npages");
        map0 = kv(line, "map0");
        map1 = kv(line, "map1");
        map2 = kv(line, "map2");
        map3 = kv(line, "map3");

        key = "SQ|" sqn;
        queue_type[key] = "SQ";
        queue_id[key] = sqn;
        queue_pdev[key] = pdev;
        queue_ix_a[key] = ch_ix;
        queue_ix_b[key] = txq_ix;
        queue_db[key] = db_dma;
        queue_npages[key] = npages;
        queue_map0[key] = map0;
        queue_map1[key] = map1;
        queue_map2[key] = map2;
        queue_map3[key] = map3;
        queue_seen[key] = 1;
    }

    if (type == "RQ_OPEN" || type == "RQ_CUR") {
        pdev = kv(line, "pdev");
        ix = kv(line, "ix");
        rqn = kv(line, "rqn");
        wq_type = kv(line, "wq_type");
        db_dma = kv(line, "db_dma");
        npages = kv(line, "npages");
        map0 = kv(line, "map0");
        map1 = kv(line, "map1");
        map2 = kv(line, "map2");
        map3 = kv(line, "map3");

        key = "RQ|" rqn;
        queue_type[key] = "RQ";
        queue_id[key] = rqn;
        queue_pdev[key] = pdev;
        queue_ix_a[key] = ix;
        queue_ix_b[key] = wq_type;
        queue_db[key] = db_dma;
        queue_npages[key] = npages;
        queue_map0[key] = map0;
        queue_map1[key] = map1;
        queue_map2[key] = map2;
        queue_map3[key] = map3;
        queue_seen[key] = 1;
    }

    if (type == "RAW_DMA_MAP") {
        pdev = kv(line, "pdev");
        sz = kv(line, "size");
        dma = kv(line, "dma");

        pdev_count[pdev] += 1;
        pdev_bytes[pdev] += sz + 0;

        if (!(pdev in pdev_first_dma)) {
            pdev_first_dma[pdev] = dma;
        }
        pdev_last_dma[pdev] = dma;

        sec = int(NR / 1000);
        sec_count[sec] += 1;
        sec_bytes[sec] += sz + 0;
        raw_total += 1;
        raw_bytes_total += sz + 0;
    }
}

END {
    print "queue_type,queue_id,pdev,ix_or_ch_ix,wq_type_or_txq_ix,db_dma,npages,map0,map1,map2,map3" > out_queue;

    queue_total = 0;
    rq_total = 0;
    sq_total = 0;

    for (k in queue_seen) {
        queue_total += 1;
        if (queue_type[k] == "RQ") rq_total += 1;
        if (queue_type[k] == "SQ") sq_total += 1;

        print queue_type[k], queue_id[k], queue_pdev[k], queue_ix_a[k], queue_ix_b[k], queue_db[k], queue_npages[k], queue_map0[k], queue_map1[k], queue_map2[k], queue_map3[k] >> out_queue;
    }

    print "pdev,count,total_bytes,first_dma,last_dma" > out_pdev;
    pdev_total = 0;
    for (p in pdev_count) {
        pdev_total += 1;
        print p, pdev_count[p], pdev_bytes[p], pdev_first_dma[p], pdev_last_dma[p] >> out_pdev;
    }

    print "bucket_index,raw_dma_count,total_bytes" > out_rate;
    for (s in sec_count) {
        print s, sec_count[s], sec_bytes[s] >> out_rate;
    }

    print "MLX5 exact DMA parse summary" > out_summary;
    print "Input log: " FILENAME >> out_summary;
    print "Unique queues: " queue_total " (RQ=" rq_total ", SQ=" sq_total ")" >> out_summary;
    print "Unique pdev in RAW_DMA_MAP: " pdev_total >> out_summary;
    print "Total RAW_DMA_MAP events: " raw_total >> out_summary;
    print "Total RAW_DMA_MAP bytes: " raw_bytes_total >> out_summary;
    print "" >> out_summary;
    print "Generated files:" >> out_summary;
    print "- " out_queue >> out_summary;
    print "- " out_pdev >> out_summary;
    print "- " out_rate >> out_summary;
}
' "$FILTERED_LOG"

echo "Generated:"
echo "  $OUT_SUMMARY"
echo "  $OUT_QUEUE"
echo "  $OUT_PDEV_DMA"
echo "  $OUT_DMA_RATE"