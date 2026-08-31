## Description
Tool to parse the perf report and perf hotspots to generate tables for comparsion and md file for reading;


## tool:
[perf_compare_tables.py](perf_compare_tables.py)




## How to used it
新增工具：

perf_compare_tables.py
已验证生成的示例输出：

tool_report_compare.md
tool_report_compare.csv
tool_hotspots_compare.md
tool_hotspots_compare.csv
使用方式（支持未来新增配置）：

生成 report 类型对比表
python3 perf_compare_tables.py --type report --input snc0-default=/home/mz/redis/redis_perf/snc0-default-redis_report.txt --input snc1-default-irq-snc1=/home/mz/redis/redis_perf/snc1-default-redis-irq-snc1_report.txt --input snc1-opt-irq-snc1=/home/mz/redis/redis_perf/snc1-opt-redis-irq-snc1_report.txt --sort metric --out-md /home/mz/redis/redis_perf/my_report_compare.md --out-csv /home/mz/redis/redis_perf/my_report_compare.csv

生成 hotspots 类型对比表
python3 perf_compare_tables.py --type hotspots --input snc0-default=/home/mz/redis/redis_perf/snc0-default-redis_hotspots.txt --input snc1-default-irq-snc1=/home/mz/redis/redis_perf/snc1-default-redis-irq-snc1_hotspots.txt --input snc1-opt-irq-snc1=/home/mz/redis/redis_perf/snc1-opt-redis-irq-snc1_hotspots.txt --sort max --out-md /home/mz/redis/redis_perf/my_hotspots_compare.md --out-csv /home/mz/redis/redis_perf/my_hotspots_compare.csv

参数说明：

--type: report 或 hotspots
--input: 可重复传入，格式为 配置名=文件路径，最少 2 组
--out-md: 输出 markdown 表格
--out-csv: 输出 csv 表格
--sort: metric 按指标名排序，max 按各配置最大值排序，first 按第一列配置排序
--precision: 小数位数，默认 2
--stdout: 直接打印 markdown 到终端



#### update tools
支持批量处理文件
已实测生成（一次命令同时产出 report + hotspots）：

auto_compare_report.md
auto_compare_report.csv
auto_compare_hotspots.md
auto_compare_hotspots.csv
一键用法如下（在 redis_perf 目录）：
python3 perf_compare_tables.py --auto-pair --batch-dir . --out-prefix auto_compare --sort max

参数说明（新增）：

--auto-pair
自动扫描并配对同前缀的 *_report.txt 和 *_hotspots.txt，然后两类都生成。
--batch-dir
扫描目录，默认是当前目录。
--out-prefix
输出前缀，会生成 4 个文件：
前缀_report.md, 前缀_report.csv, 前缀_hotspots.md, 前缀_hotspots.csv
--report-suffix 和 --hotspots-suffix
可改后缀匹配规则，适配你后续新命名。
--sort 和 --precision
继续支持排序方式和小数位数控制。