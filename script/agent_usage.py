#!/usr/bin/env python3
"""只读汇总 Agent 用量；仅统计 usage.jsonl，不从旧聊天推算账单。"""

import argparse
from collections import defaultdict
import json
from pathlib import Path


def summarize(records):
    latest = {}
    for record in records:
        previous = latest.get(record["id"])
        # Copied files can contain an older running snapshot in the same second.
        order = lambda r: (r["updatedAt"], r["state"] != "running")
        if previous is None or order(record) >= order(previous):
            latest[record["id"]] = record
    groups = defaultdict(lambda: defaultdict(int))
    for record in latest.values():
        key = (record.get("provider") or "unknown", record["family"], record["model"], record["purpose"])
        row = groups[key]
        row["calls"] += 1
        row[record["state"]] += 1
        if record.get("contextWindow") is None:
            row["unknown_window"] += 1
        usage = record.get("usage")
        if usage is None:
            row["unknown_usage"] += 1
            continue
        if record["state"] != "completed":
            row["partial_usage"] += 1
        row["reported_usage"] += 1
        uncached = usage["inputTokens"]
        read = usage.get("cacheReadTokens") or 0
        write = usage.get("cacheWriteTokens") or 0
        row["input"] += uncached + read + write
        row["output"] += usage["outputTokens"]
        if usage.get("cacheWriteTokens") is not None:
            row["reported_cache_write"] += 1
            row["cache_write"] += write
        if usage.get("cacheReadTokens") is not None:
            row["reported_cache"] += 1
            row["cache_read"] += read
            row["cache_known_input"] += uncached + read + write
        else:
            row["unknown_cache"] += 1
    return [dict(provider=k[0], family=k[1], model=k[2], purpose=k[3], **v)
            for k, v in sorted(groups.items())]


def read_records(root):
    paths = [root] if root.is_file() else sorted(root.rglob("usage.jsonl"))
    for path in paths:
        with path.open() as source:
            for number, line in enumerate(source, 1):
                try:
                    yield json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(f"用量记录无法解析：{path}:{number}") from error


def self_check():
    record = dict(id="a", updatedAt="2026-09-16T00:00:00Z", provider="test", family="mock",
                  model="model", purpose="answer", state="running")
    known = dict(record, state="completed", usage=dict(inputTokens=100, outputTokens=20,
                                                      cacheReadTokens=900))
    rows = summarize([record, known, record, known,
                      dict(record, id="b", state="failed"),
                      dict(record, id="c", state="cancelled", usage=dict(inputTokens=50, outputTokens=5))])
    row, = rows
    assert row["calls"] == 3 and row["unknown_usage"] == 1
    assert row["input"] == 1050 and row["output"] == 25
    assert row["reported_cache"] == 1 and row["unknown_cache"] == 1
    assert row["cache_read"] / row["cache_known_input"] == .9
    assert row["partial_usage"] == 1
    print("用量汇总检查通过")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, help="会话根目录或 usage.jsonl 文件")
    parser.add_argument("--json", action="store_true", help="输出结构化统计")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return
    if args.root is None or not args.root.exists():
        parser.error("请指定存在的会话目录或用量文件")
    rows = summarize(read_records(args.root))
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return
    print("只统计新用量账本；未知不是零，未正常结束的已报用量是下限。")
    print("供应商 / 协议 / 模型 / 用途 | 调用 | 用量未知 | 部分用量 | 已报输入 | 已报输出 | 缓存读/写 | 缓存字段覆盖 | 已报样本命中率 | 窗口未知")
    for row in rows:
        count = row.get("cache_known_input", 0)
        rate = f'{row.get("cache_read", 0) / count:.2%}' if count else "未知"
        reported = row.get("reported_usage", 0)
        input_text = str(row.get("input", 0)) if reported else "未知"
        output_text = str(row.get("output", 0)) if reported else "未知"
        read_text = str(row.get("cache_read", 0)) if row.get("reported_cache", 0) else "未报"
        write_text = str(row.get("cache_write", 0)) if row.get("reported_cache_write", 0) else "未报"
        print(f'{row["provider"]} / {row["family"]} / {row["model"]} / {row["purpose"]} | '
              f'{row["calls"]} | {row.get("unknown_usage", 0)} | {row.get("partial_usage", 0)} | '
              f'{input_text} | {output_text} | '
              f'{read_text}/{write_text} | '
              f'{row.get("reported_cache", 0)}/{row["calls"]} | {rate} | {row.get("unknown_window", 0)}')
    if not rows:
        print("没有新用量记录，不能据此声称零消耗。")


if __name__ == "__main__":
    main()
