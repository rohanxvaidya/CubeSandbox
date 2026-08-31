#!/usr/bin/env python3
"""
EMON Autonomous Agent Configuration
这个文件定义了自主EMON分析流程的所有步骤和决策逻辑
"""

class EMONAgentConfig:
    """Agent 工作流配置"""
    
    # Agent 的生命周期阶段
    PHASES = {
        "DISCOVER": {
            "description": "发现并索引所有 .dat 文件",
            "tools": ["find", "grep"],
            "decision_points": ["file_count", "total_size", "data_quality"]
        },
        "RENAME": {
            "description": "自动重命名和组织文件",
            "tools": ["bash_script"],
            "decision_points": ["naming_convention", "conflict_resolution"]
        },
        "PROCESS": {
            "description": "自主选择处理策略",
            "tools": ["emon_tool.sh", "EDP"],
            "decision_points": ["file_size", "event_set", "output_format"]
        },
        "ANALYZE": {
            "description": "自动生成对比报告",
            "tools": ["openpyxl", "pandas"],
            "decision_points": ["baseline_selection", "metrics", "anomalies"]
        },
        "REPORT": {
            "description": "生成最终报告和可视化",
            "tools": ["matplotlib", "openpyxl"],
            "decision_points": ["chart_type", "comparison_groups"]
        }
    }
    
    # Agent 的决策规则示例
    DECISION_RULES = {
        "file_size": {
            "rule": "if size > 500MB: use_parallel_processing",
            "rule": "if size < 100MB: use_direct_processing"
        },
        "baseline_selection": {
            "rule": "自动选择最近的同类型测试作为基线"
        },
        "anomaly_detection": {
            "rule": "如果性能差异 > 10%，标记为异常"
        }
    }
    
    # Agent 的反馈循环
    FEEDBACK_LOOP = [
        "Execute Phase",
        "Check Results (get_errors)",
        "Decision: Continue or Adjust?",
        "Log to todo_list",
        "Next Phase"
    ]


if __name__ == "__main__":
    print("=" * 60)
    print("EMON Autonomous Agent 配置已加载")
    print("=" * 60)
    for phase, details in EMONAgentConfig.PHASES.items():
        print(f"\n【{phase}】")
        print(f"  描述: {details['description']}")
        print(f"  工具: {', '.join(details['tools'])}")
        print(f"  决策点: {', '.join(details['decision_points'])}")
