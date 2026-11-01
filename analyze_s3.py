#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "boto3",
# ]
# ///
"""
S3 Storage Usage Analyzer for ploys3 configuration
Supports:
  - Reading server configs from ~/.config/ploys3/config.json
  - Full recursive scan with local caching
  - Unified sorting (Files and Folders ranked together by size)
  - Pure Directory ranking & Pure File ranking
  - File extension breakdown
  - Cleanup / Anomaly detection (e.g. .git leaks, stray build files, empty files)
  - CSV export for detailed Excel/Spreadsheet inspection
"""

import os
import sys
import json
import argparse
import csv
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Any, Tuple

CONFIG_FILE = os.path.expanduser("~/.config/ploys3/config.json")
CACHE_DIR = os.path.expanduser("~/.cache/ploys3")

def format_size(size_bytes: int) -> str:
    """Format bytes to human-readable string."""
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(size_bytes)
    idx = 0
    while size >= 1024.0 and idx < len(units) - 1:
        size /= 1024.0
        idx += 1
    return f"{size:7.2f} {units[idx]}"

def load_server_config(config_path: str, server_name: str = "Qiniu") -> dict:
    if not os.path.exists(config_path):
        print(f"Error: 配置文件未找到: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    servers = data.get("servers", [])
    matched = None
    for s in servers:
        if s.get("name", "").lower() == server_name.lower():
            matched = s
            break
        if s.get("id") == server_name:
            matched = s
            break

    if not matched:
        available = [f"{s.get('name')} (id: {s.get('id')})" for s in servers]
        print(f"Error: 未找到服务器 '{server_name}'。可用服务器: {', '.join(available)}", file=sys.stderr)
        sys.exit(1)

    return matched

def get_s3_client(server_cfg: dict):
    import boto3
    from botocore.config import Config

    return boto3.client(
        "s3",
        endpoint_url=server_cfg.get("address"),
        aws_access_key_id=server_cfg.get("accessKeyId"),
        aws_secret_access_key=server_cfg.get("secretAccessKey"),
        region_name=server_cfg.get("region") or "cn-east-1",
        config=Config(
            connect_timeout=10,
            read_timeout=30,
            retries={"max_attempts": 3}
        )
    )

def fetch_bucket_objects(s3_client, bucket: str, cache_file: str, force_refresh: bool = False) -> List[dict]:
    if not force_refresh and os.path.exists(cache_file):
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                cached_data = json.load(f)
            cache_time = cached_data.get("timestamp", 0)
            items = cached_data.get("items", [])
            dt_str = datetime.fromtimestamp(cache_time).strftime("%Y-%m-%d %H:%M:%S")
            print(f"[*] 使用本地缓存文件 ({dt_str}, 共 {len(items)} 个文件): {cache_file}")
            print(f"[*] 如需重新全量抓取，请添加 --refresh 参数\n")
            return items
        except Exception as e:
            print(f"[!] 读取缓存失败，将重新从云端抓取: {e}", file=sys.stderr)

    print(f"[*] 正在从 S3 存储桶 [{bucket}] 获取全量对象列表...")
    paginator = s3_client.get_paginator("list_objects_v2")
    items = []
    page_no = 0
    total_bytes = 0

    for page in paginator.paginate(Bucket=bucket):
        page_no += 1
        contents = page.get("Contents", [])
        for obj in contents:
            items.append({
                "key": obj["Key"],
                "size": obj["Size"],
                "last_modified": obj["LastModified"].isoformat() if hasattr(obj["LastModified"], "isoformat") else str(obj["LastModified"]),
                "storage_class": obj.get("StorageClass", "STANDARD")
            })
            total_bytes += obj["Size"]
        print(f"\r    -> 已获取 {page_no} 页，共 {len(items):,} 个对象 ({format_size(total_bytes).strip()})...", end="", flush=True)

    print(f"\n[*] 抓取完毕，共 {len(items):,} 个对象，总容量 {format_size(total_bytes).strip()}。")

    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    with open(cache_file, "w", encoding="utf-8") as f:
        json.dump({"timestamp": datetime.now().timestamp(), "items": items}, f)
    print(f"[*] 已写入本地分析缓存: {cache_file}\n")

    return items

def analyze_data(items: List[dict], max_folder_depth: int = 3):
    total_size = sum(item["size"] for item in items)
    total_files = len(items)

    # 1. 文件夹聚合：统计每个目录前缀的递归大小与直接文件数
    # 例如 key: "a/b/c/file.png" -> "a/", "a/b/", "a/b/c/"
    dir_sizes = defaultdict(int)
    dir_counts = defaultdict(int)
    dir_direct_files = defaultdict(int)
    dir_direct_size = defaultdict(int)

    # 2. 文件扩展名分布
    ext_sizes = defaultdict(int)
    ext_counts = defaultdict(int)

    # 3. 根目录直接文件
    root_files = []

    # 4. 异常/疑似垃圾文件识别
    anomalies = []

    for item in items:
        key = item["key"]
        size = item["size"]
        parts = key.split("/")

        # 扩展名
        base_name = parts[-1]
        _, ext = os.path.splitext(base_name)
        ext = ext.lower() if ext else "(无后缀)"
        ext_sizes[ext] += size
        ext_counts[ext] += 1

        # 根目录或目录层次
        if len(parts) == 1:
            root_files.append(item)
            dir_direct_files["/ (根目录文件)"] += 1
            dir_direct_size["/ (根目录文件)"] += size
        else:
            parent_dir = "/".join(parts[:-1]) + "/"
            dir_direct_files[parent_dir] += 1
            dir_direct_size[parent_dir] += size

            # 递归给所有父级累加
            for i in range(1, len(parts)):
                prefix = "/".join(parts[:i]) + "/"
                dir_sizes[prefix] += size
                dir_counts[prefix] += 1

        # 异常检测
        if key.startswith(".git/"):
            anomalies.append(("Git 版本控制泄漏", key, size, "意外上传的 .git 仓库文件，应清理"))
        elif base_name in [".DS_Store", "Thumbs.db"]:
            anomalies.append(("系统临时文件", key, size, "操作系统缩略图/元数据残留"))
        elif size == 0:
            anomalies.append(("0字节空对象", key, size, "空文件或多余占位符"))
        elif key.strip() != key or any(p.strip() == "" for p in parts[:-1]):
            anomalies.append(("异常空格/特殊字符Key", key, size, "含有前后空格或空路径段"))
        elif base_name.endswith(".map"):
            anomalies.append(("前端 SourceMap", key, size, "代码调试源文件，可按需清理"))

    return {
        "total_size": total_size,
        "total_files": total_files,
        "dir_sizes": dir_sizes,
        "dir_counts": dir_counts,
        "dir_direct_files": dir_direct_files,
        "dir_direct_size": dir_direct_size,
        "ext_sizes": ext_sizes,
        "ext_counts": ext_counts,
        "root_files": root_files,
        "anomalies": anomalies,
    }

def print_summary(analysis: dict, bucket_name: str, server_name: str, cdn_url: str):
    print("=" * 80)
    print(f"📊 存储资源总览 - [{server_name}] 存储桶: {bucket_name}")
    print(f"   CDN 加速域名: {cdn_url or '未配置'}")
    print(f"   总文件数量  : {analysis['total_files']:,} 个")
    print(f"   总占用空间  : {format_size(analysis['total_size']).strip()} ({analysis['total_size']:,} 字节)")
    print("=" * 80)

def print_extensions(analysis: dict, top_n: int = 10):
    print(f"\n📂 文件类型 (扩展名) 空间分布 (前 {top_n} 类):")
    print("-" * 80)
    print(f"{'扩展名':<15} | {'文件数':>8} | {'总大小':>12} | {'占比':>8} | {'平均大小':>10}")
    print("-" * 80)

    total_size = analysis["total_size"] or 1
    sorted_exts = sorted(analysis["ext_sizes"].items(), key=lambda x: x[1], reverse=True)[:top_n]
    for ext, size in sorted_exts:
        count = analysis["ext_counts"][ext]
        pct = (size / total_size) * 100
        avg = size / count if count else 0
        print(f"{ext:<15} | {count:>8,d} | {format_size(size):>12} | {pct:>7.2f}% | {format_size(int(avg)):>10}")

def print_unified_ranking(items: List[dict], analysis: dict, top_n: int = 30, max_depth: int = 2):
    """
    文件与文件夹一起参与排序
    为了避免深层嵌套导致每个前缀重复刷屏，只纳入 <= max_depth 深度的文件夹参与竞争
    """
    total_size = analysis["total_size"] or 1
    candidates = []

    # 1. 文件夹候选
    for d, size in analysis["dir_sizes"].items():
        depth = d.count("/")
        if depth <= max_depth:
            candidates.append({
                "type": "DIR",
                "name": d,
                "size": size,
                "count": analysis["dir_counts"][d],
                "extra": f"{analysis['dir_counts'][d]:,} 文件"
            })

    # 2. 单个文件候选
    for it in items:
        candidates.append({
            "type": "FILE",
            "name": it["key"],
            "size": it["size"],
            "count": 1,
            "extra": it["last_modified"][:10]
        })

    candidates.sort(key=lambda x: x["size"], reverse=True)

    print(f"\n🏆 文件夹与文件综合大小排行榜 (前 {top_n} 名, 文件夹深度限制<={max_depth}):")
    print("-" * 96)
    print(f"{'排名':<4} | {'类型':<6} | {'占用空间':>12} | {'占比':>8} | {'文件数/修改日期':<14} | {'路径/文件名'}")
    print("-" * 96)

    for rank, entry in enumerate(candidates[:top_n], start=1):
        type_str = f"[{entry['type']}]"
        pct = (entry["size"] / total_size) * 100
        name = entry["name"]
        if len(name) > 48:
            name = name[:20] + "..." + name[-25:]
        print(f"{rank:<4} | {type_str:<6} | {format_size(entry['size']):>12} | {pct:>7.2f}% | {entry['extra']:<14} | {entry['name']}")

def print_top_directories(analysis: dict, top_n: int = 20, max_depth: int = 2):
    total_size = analysis["total_size"] or 1
    dirs = [
        (d, size, analysis["dir_counts"][d])
        for d, size in analysis["dir_sizes"].items()
        if d.count("/") <= max_depth
    ]
    dirs.sort(key=lambda x: x[1], reverse=True)

    print(f"\n📁 文件夹占用排行 (前 {top_n} 名, 目录层级<={max_depth}):")
    print("-" * 88)
    print(f"{'排名':<4} | {'总空间':>12} | {'占比':>8} | {'包含文件数':>10} | {'目录路径'}")
    print("-" * 88)

    for rank, (d, size, count) in enumerate(dirs[:top_n], start=1):
        pct = (size / total_size) * 100
        print(f"{rank:<4} | {format_size(size):>12} | {pct:>7.2f}% | {count:>10,d} | {d}")

def print_top_files(items: List[dict], top_n: int = 25, cdn_url: str = ""):
    sorted_files = sorted(items, key=lambda x: x["size"], reverse=True)[:top_n]
    print(f"\n📄 单个超大文件排行榜 (前 {top_n} 名):")
    print("-" * 96)
    print(f"{'排名':<4} | {'文件大小':>12} | {'最后修改日期':<19} | {'文件路径'}")
    print("-" * 96)

    for rank, it in enumerate(sorted_files, start=1):
        lm = it["last_modified"][:19].replace("T", " ")
        print(f"{rank:<4} | {format_size(it['size']):>12} | {lm:<19} | {it['key']}")

def print_anomalies_and_suggestions(analysis: dict):
    anomalies = analysis["anomalies"]
    root_files = analysis["root_files"]
    print("\n🔍 空间优化诊断与潜在清理建议:")
    print("=" * 80)

    # 1. 根目录直接散落文件
    if root_files:
        root_size = sum(f["size"] for f in root_files)
        print(f"1. ⚠️  根目录直接散落文件: 共 {len(root_files):,} 个，占用 {format_size(root_size).strip()}")
        print(f"    说明: 根目录下散落了大量旧图片/动图（很多为 2016-2017 年历史文章附件）。")
        print(f"    建议: 若网站已迁移或不再引用，可考虑归档或整理入独立子目录。")

    # 2. 异常敏感或泄漏文件
    git_items = [a for a in anomalies if a[0] == "Git 版本控制泄漏"]
    if git_items:
        git_size = sum(a[2] for a in git_items)
        print(f"\n2. 🚨 发现 .git 仓库泄漏/意外同步: 共 {len(git_items)} 个文件，占用 {format_size(git_size).strip()}")
        print(f"    说明: S3 桶中存在 `.git/HEAD`, `.git/config` 等文件，严重威胁代码与密钥安全，建议优先彻底删除！")

    # 3. 0字节空文件
    zero_files = [a for a in anomalies if a[0] == "0字节空对象"]
    if zero_files:
        print(f"\n3. ℹ️  0 字节空文件: 共 {len(zero_files)} 个")
        print(f"    说明: 大多数是目录占位标或无效请求生成的空文件，可清理。")

    # 4. WordPress / 动效 / 临时文件
    wp_dirs = [d for d in analysis["dir_sizes"] if d.startswith("wp-")]
    if wp_dirs:
        wp_size = sum(analysis["dir_sizes"][d] for d in ["wp-content/", "wp-includes/", "wp-admin/"] if d in analysis["dir_sizes"])
        print(f"\n4. ℹ️  WordPress 残留文件: 占用约 {format_size(wp_size).strip()}")
        print(f"    说明: 包含很多 .php 程序代码及旧插件静态资源，若该网站已不运行 WordPress，可整体清理。")

    # 5. ai-server 占比
    ai_server_size = analysis["dir_sizes"].get("ai-server/", 0)
    if ai_server_size:
        total_size = analysis["total_size"] or 1
        pct = (ai_server_size / total_size) * 100
        print(f"\n5. 💡 核心存储大头: `ai-server/` 目录")
        print(f"    空间占用: {format_size(ai_server_size).strip()} (占全桶 {pct:.1f}%)，共 {analysis['dir_counts'].get('ai-server/', 0):,} 个文件。")
        print(f"    说明: 里面存储了大量 AIGC 生成的 PNG 原图（平均每个图 1~12 MB）。")
        print(f"    建议: 如需节省 80% 以上成本，可将这些旧 PNG 批量转换为 WebP/AVIF，或按生成日期（如 90 天前）归档转低频/删除。")
    print("=" * 80)

def export_to_csv(items: List[dict], analysis: dict, csv_path: str, cdn_url: str):
    print(f"\n[*] 正在导出全量分析数据到 CSV: {csv_path} ...")
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(["类型", "路径/名称", "大小(字节)", "大小(人类可读)", "文件数(目录有效)", "最后修改时间", "公开访问URL"])

        # 1. 导出所有聚合目录
        for d, size in sorted(analysis["dir_sizes"].items(), key=lambda x: x[1], reverse=True):
            writer.writerow([
                "DIR",
                d,
                size,
                format_size(size).strip(),
                analysis["dir_counts"][d],
                "-",
                "-"
            ])

        # 2. 导出所有文件
        base_url = (cdn_url.rstrip("/") + "/") if cdn_url else ""
        for it in sorted(items, key=lambda x: x["size"], reverse=True):
            url = f"{base_url}{it['key']}" if base_url else ""
            writer.writerow([
                "FILE",
                it["key"],
                it["size"],
                format_size(it["size"]).strip(),
                1,
                it["last_modified"],
                url
            ])

    print(f"[*] 导出成功！可直接使用 Excel、Numbers 或 WPS 打开此文件进行多维筛选分析: {csv_path}")

def main():
    parser = argparse.ArgumentParser(description="分析 ploys3 配置中的 S3 服务存储资源占用情况")
    parser.add_argument("--config", default=CONFIG_FILE, help=f"ploys3 配置文件路径 (默认: {CONFIG_FILE})")
    parser.add_argument("--server", default="Qiniu", help="要分析的服务器名称或 ID (默认: Qiniu)")
    parser.add_argument("--top", type=int, default=30, help="排行榜展示数量 (默认: 30)")
    parser.add_argument("--depth", type=int, default=2, help="参与排序的文件夹最大层级深度 (默认: 2)")
    parser.add_argument("--refresh", action="store_true", help="强制从云端重新拉取，忽略本地缓存")
    parser.add_argument("--export", type=str, default="", help="导出全量排序清单为指定 CSV 文件路径")
    parser.add_argument("--files-only", action="store_true", help="仅显示文件排行")
    parser.add_argument("--dirs-only", action="store_true", help="仅显示目录排行")

    args = parser.parse_args()

    server_cfg = load_server_config(args.config, args.server)
    bucket = server_cfg.get("bucket")
    cdn_url = server_cfg.get("cdnUrl") or ""

    if not bucket:
        print(f"Error: 服务器 [{server_cfg.get('name')}] 未配置 bucket", file=sys.stderr)
        sys.exit(1)

    cache_file = os.path.join(CACHE_DIR, f"{server_cfg.get('name', 's3')}_{bucket}_cache.json")
    s3_client = get_s3_client(server_cfg)

    items = fetch_bucket_objects(s3_client, bucket, cache_file, force_refresh=args.refresh)
    analysis = analyze_data(items, max_folder_depth=args.depth)

    # 1. 总览
    print_summary(analysis, bucket, server_cfg.get("name", "Qiniu"), cdn_url)

    # 2. 扩展名分布
    print_extensions(analysis, top_n=10)

    # 3. 排序视图
    if args.dirs_only:
        print_top_directories(analysis, top_n=args.top, max_depth=args.depth)
    elif args.files_only:
        print_top_files(items, top_n=args.top, cdn_url=cdn_url)
    else:
        # 文件夹与文件共同排序
        print_unified_ranking(items, analysis, top_n=args.top, max_depth=args.depth)
        print_top_directories(analysis, top_n=15, max_depth=args.depth)
        print_top_files(items, top_n=15, cdn_url=cdn_url)

    # 4. 优化诊断与建议
    print_anomalies_and_suggestions(analysis)

    # 5. CSV 导出
    if args.export:
        export_to_csv(items, analysis, args.export, cdn_url)

if __name__ == "__main__":
    main()
