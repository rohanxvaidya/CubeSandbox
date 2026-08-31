in this project, have add flow_trace logging function, 
please use `DSA_PERF_MICROS_FLOW_TRACE` to enable the logging function.


 DSA_PERF_MICROS_FLOW_TRACE=1 DSA_PERF_MICROS_LOG_LEVEL=debug ./src/dsa_perf_micros -k 6 -u -i 10 -n 128 -s 1024k -o3 -w 0 > dsa_perf_micros_user_memcopy.log


DSA_PERF_MICROS_FLOW_TRACE=1 DSA_PERF_MICROS_LOG_LEVEL=debug ./src/dsa_perf_micros -k 6 -u -i 10 -n 128 -s 1024k -o3 -w 0 > dsa_perf_micros_user_memcopy_uio.log 2>&1
