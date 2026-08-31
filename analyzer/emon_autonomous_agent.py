#!/usr/bin/env python3
"""
EMON Autonomous Agent 主循环
演示如何在 VS Code 编辑器内实现自主化工作流
"""

import os
import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime

class EMONAutonomousAgent:
    """
    自主EMON分析Agent
    在VS Code编辑器内通过以下机制运行：
    - run_in_terminal: 执行 bash 命令
    - read_file: 读取日志和结果
    - get_errors: 检查执行错误
    - manage_todo_list: 追踪任务进度
    """
    
    def __init__(self, root_dir, emon_tool_path):
        self.root_dir = Path(root_dir)
        self.emon_tool = Path(emon_tool_path)
        self.state = {
            "phase": None,
            "files_discovered": [],
            "files_processed": [],
            "errors": [],
            "start_time": datetime.now().isoformat()
        }
        self.log_file = self.root_dir / ".agent_log.json"
    
    def log_state(self):
        """保存Agent状态到日志（用于 get_errors 和 manage_todo_list）"""
        with open(self.log_file, 'w') as f:
            json.dump(self.state, f, indent=2)
        print(f"[AGENT] 状态已保存: {self.log_file}")
    
    def run_phase(self, phase_name):
        """
        执行一个阶段
        这里模拟我在VS Code中调用 run_in_terminal 工具
        """
        self.state["phase"] = phase_name
        print(f"\n{'='*60}")
        print(f"【阶段】{phase_name}")
        print(f"{'='*60}")
        
        if phase_name == "DISCOVER":
            return self._phase_discover()
        elif phase_name == "RENAME":
            return self._phase_rename()
        elif phase_name == "PROCESS":
            return self._phase_process()
        elif phase_name == "ANALYZE":
            return self._phase_analyze()
        elif phase_name == "REPORT":
            return self._phase_report()
    
    def _phase_discover(self):
        """
        Phase 1: 发现并索引所有 .dat 文件
        使用: grep_search 和 file_search
        """
        print("[DISCOVER] 扫描所有 .dat 文件...")
        
        try:
            result = subprocess.run(
                f"find {self.root_dir} -type f -name '*.dat' | head -20",
                shell=True, capture_output=True, text=True
            )
            dat_files = result.stdout.strip().split('\n')
            self.state["files_discovered"] = [f for f in dat_files if f]
            
            print(f"[DISCOVER] ✅ 发现 {len(self.state['files_discovered'])} 个 .dat 文件")
            return True
        except Exception as e:
            self.state["errors"].append(f"DISCOVER 阶段失败: {str(e)}")
            print(f"[DISCOVER] ❌ 错误: {str(e)}")
            return False
    
    def _phase_rename(self):
        """
        Phase 2: 自动重命名
        使用: run_in_terminal 调用 batch_rename_move_process_emon.sh
        """
        print("[RENAME] 执行文件重命名...")
        
        if not self.emon_tool.exists():
            self.state["errors"].append(f"EMON工具不存在: {self.emon_tool}")
            print(f"[RENAME] ❌ 工具路径错误")
            return False
        
        try:
            # 这里模拟调用 run_in_terminal
            cmd = f"bash {self.emon_tool} {self.root_dir}"
            print(f"[RENAME] 执行: {cmd}")
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                print(f"[RENAME] ✅ 重命名完成")
                return True
            else:
                self.state["errors"].append(f"重命名失败: {result.stderr}")
                print(f"[RENAME] ❌ {result.stderr}")
                return False
        except Exception as e:
            self.state["errors"].append(f"RENAME 阶段异常: {str(e)}")
            print(f"[RENAME] ❌ 异常: {str(e)}")
            return False
    
    def _phase_process(self):
        """
        Phase 3: 自主选择处理策略
        使用: get_errors 检查结果
        """
        print("[PROCESS] 自主决策处理策略...")
        
        strategies = []
        for dat_file in self.state["files_discovered"][:5]:  # 示例：处理前5个
            file_path = Path(dat_file)
            file_size_mb = file_path.stat().st_size / (1024*1024) if file_path.exists() else 0
            
            # 自主决策: 根据文件大小选择策略
            if file_size_mb > 500:
                strategy = "parallel"
            elif file_size_mb < 100:
                strategy = "direct"
            else:
                strategy = "batch"
            
            strategies.append({"file": str(file_path), "size_mb": file_size_mb, "strategy": strategy})
            print(f"  {file_path.name}: {file_size_mb:.1f}MB → {strategy}")
        
        self.state["strategies"] = strategies
        print(f"[PROCESS] ✅ 已确定处理策略")
        return True
    
    def _phase_analyze(self):
        """
        Phase 4: 自动生成对比分析
        使用: 虚拟化分析逻辑（实际会读取Excel/CSV）
        """
        print("[ANALYZE] 执行数据对比分析...")
        
        # 这里应该读取处理后的 xlsx 文件，与基线对比
        print("[ANALYZE] 扫描输出目录...")
        
        analysis_results = {
            "total_files": len(self.state["files_discovered"]),
            "processing_status": "in_progress",
            "anomalies_detected": 0
        }
        
        self.state["analysis"] = analysis_results
        print(f"[ANALYZE] ✅ 分析完成")
        return True
    
    def _phase_report(self):
        """
        Phase 5: 生成最终报告
        """
        print("[REPORT] 生成最终报告...")
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "total_files": len(self.state["files_discovered"]),
            "processed": len(self.state["files_discovered"]),
            "errors": len(self.state["errors"]),
            "status": "completed" if not self.state["errors"] else "partial"
        }
        
        self.state["report"] = report
        print(f"[REPORT] ✅ 报告生成完成")
        return True
    
    def execute_full_workflow(self):
        """
        执行完整工作流
        这是Agent的主循环 - 演示反馈循环
        """
        phases = ["DISCOVER", "RENAME", "PROCESS", "ANALYZE", "REPORT"]
        
        for phase in phases:
            success = self.run_phase(phase)
            self.log_state()  # 保存状态（供 get_errors 读取）
            
            if not success:
                print(f"\n[AGENT] ⚠️  {phase} 阶段失败，可选择继续或停止")
                # 在实际场景中，这里会通过 manage_todo_list 报告给用户
                user_input = input("继续? (y/n): ").strip().lower()
                if user_input != 'y':
                    print("[AGENT] 工作流已停止")
                    break
        
        print("\n" + "="*60)
        print("[AGENT] 完整工作流执行完成")
        print("="*60)
        self.log_state()


def main():
    # 示例配置
    root_dir = "/home/mz/0_work/1_ByteDance/bytedance_cxl/emon"
    emon_tool = "/root/Mydata-SPRinspur22/0_work/tools/Storage-performance-analysis/analyzer/batch_rename_move_process_emon.sh"
    
    agent = EMONAutonomousAgent(root_dir, emon_tool)
    agent.execute_full_workflow()


if __name__ == "__main__":
    main()
