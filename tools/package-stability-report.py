"""Summarize wall-clock soak evidence; raw frames and player fixtures stay ignored."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def package(source, destination):
    result = read(source / "results.json")
    host = read(source / "host-summary.json")
    samples = [json.loads(line) for line in (source / "process-memory.jsonl").read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if result["failures"] or len(result["cases"]) != 8 or not host["diagnostics_clean"]:
        raise ValueError("Only a complete passing eight-case run may be packaged")
    if result["metadata"].get("frame_sampler") != "independent per-frame Node, including frames during harness coroutine waits":
        raise ValueError("Reject coroutine observation gaps; use the independent frame observer")
    durations = [case["actual_seconds"] for case in result["cases"]]
    requested = result["metadata"]["case_seconds_requested"]
    if requested < 90 or min(durations) < 90:
        raise ValueError("A short preflight cannot be presented as the 12-minute soak")
    destination.mkdir(parents=True, exist_ok=True)
    baseline = result["metadata"]["cleanup_baseline_static_mib"]
    build_info = read(Path(host["pack_path"]).parent / "build-info.json")
    recorded_pack = next(file for file in build_info["files"] if file["path"] == "Jingwei.pck")
    if recorded_pack["sha256"].upper() != host["pack_sha256"].upper():
        raise ValueError("Measured PCK hash must match its recorded source build")
    clean_memory = [entry["static_mib"] for entry in result["cleanup"]]
    operations = [dict(operation, target=case["target"], quality=case["quality"]) for case in result["cases"] for operation in case["operations"]]
    summary = {
        "runtime_pack_sha256": host["pack_sha256"],
        "runtime_source_commit": build_info["source_commit"],
        "metadata": result["metadata"],
        "actual_timed_case_seconds": sum(durations),
        "whole_session_seconds": result["session_seconds"],
        "host_wall_seconds": host["host_wall_seconds"],
        "checks": result["checks"], "failures": result["failures"],
        "boots": result["boots"], "resets": result["resets"],
        "explicit_saves": result["explicit_saves"],
        "corrupt_primary_recoveries": result["corrupt_primary_recoveries"],
        "gather_actions": result["gather_actions"], "deposits": result["deposits"],
        "injected_stones": result["injected_stones"],
        "fixture_advanced_simulated_seconds": result["fixture_advanced_simulated_seconds"],
        "process_memory_samples": host["memory_samples"],
        "working_set_sample_peak_mib": host["memory_peak_mib"],
        "process_cumulative_peak_mib": host["cumulative_peak_mib"],
        "empty_checkpoint_static_change_mib": clean_memory[-1] - baseline,
        "empty_checkpoint_first_to_last_change_mib": clean_memory[-1] - clean_memory[0],
        "same_scale_cleanup_change_mib": [{"target": result["cleanup"][i]["target"], "smooth_minus_standard_mib": clean_memory[i + 1] - clean_memory[i]} for i in range(0, 8, 2)],
        "measurement_buffer_note": "Scene-free memory still includes harness current frame/result buffers. Node/orphan/resource counts are separately recorded; the independent frame observer remains attached.",
        "cleanup": result["cleanup"], "cases": result["cases"],
        "slowest_operation": max(operations, key=lambda item: item["milliseconds"]),
        "float_comparison": "integer resources exact; floating JSON roundoff <= max(1e-12, max(abs(a),abs(b))*1e-14)",
        "limits": "12-minute capped desktop editor harness mounting shipping PCK; not release EXE performance, minimum spec, exclusive-machine benchmark or multi-hour soak",
    }
    (destination / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    names = {100000: "10万", 1000000: "100万", 10000000: "1000万", 100000000: "1亿"}
    rows = ["| 目标 / 画质 | 实际秒数 | 帧数 | p95 / p99 / 最慢 ms | >33.33ms 帧 | 清理后静态 MiB |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for case, cleanup in zip(result["cases"], result["cleanup"]):
        frame = case["frames"]
        label = "标准" if case["quality"] == "standard" else "流畅"
        rows.append(f"| {names[case['target']]} / {label} | {case['actual_seconds']:.2f} | {frame['frames']} | {frame['p95_ms']:.2f} / {frame['p99_ms']:.2f} / {frame['max_ms']:.2f} | {frame['over_33ms']} | {cleanup['static_mib']:.2f} |")
    (destination / "table.md").write_text("\n".join(rows) + "\n", encoding="utf-8")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    start = samples[0]["unix_seconds"]
    times = [(sample["unix_seconds"] - start) / 60 for sample in samples]
    fig, axes = plt.subplots(2, 1, figsize=(11, 7), gridspec_kw={"height_ratios": [2, 1]}, constrained_layout=True)
    axes[0].plot(times, [sample["working_set_mib"] for sample in samples], label="Working set (sampled 1 Hz)", color="#386a76", linewidth=1.2)
    axes[0].plot(times, [sample["private_mib"] for sample in samples], label="Private bytes", color="#ab7044", linewidth=1.1)
    for index, case in enumerate(result["cases"]):
        begin = (case["unix_start"] - start) / 60
        end = (case["unix_end"] - start) / 60
        axes[0].axvspan(begin, end, color="#547b61", alpha=.08 if index % 2 == 0 else .02)
        axes[0].text((begin + end) / 2, 1.01, f"{case['target']:,}\n{case['quality']}", transform=axes[0].get_xaxis_transform(), ha="center", fontsize=7)
    axes[0].set(xlabel="Actual wall-clock minutes (includes warmup/setup)", ylabel="Actual game process MiB")
    axes[0].legend(loc="lower right", fontsize=8)
    axes[0].grid(alpha=.18)
    values = [baseline] + clean_memory
    axes[1].plot(range(len(values)), values, color="#547b61", marker="o")
    axes[1].set_xticks(range(len(values)), ["Warmup"] + [f"{case['target']:,}\n{case['quality']}" for case in result["cases"]], fontsize=7)
    axes[1].set(ylabel="Engine static MiB", title="Scene-free checkpoints (includes harness frame/result buffers)")
    axes[1].grid(alpha=.18)
    fig.suptitle("Jingwei QA-02 | 8 real-time cases | 60 FPS cap | editor harness + shipping PCK", fontsize=12)
    fig.savefig(destination / "memory.png", dpi=150)
    plt.close(fig)
    print(json.dumps({"checks": summary["checks"], "case_seconds": summary["actual_timed_case_seconds"], "working_peak_mib": summary["working_set_sample_peak_mib"], "static_change_mib": summary["empty_checkpoint_static_change_mib"], "slowest_operation_ms": summary["slowest_operation"]["milliseconds"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "artifacts/QA02-soak-final")
    parser.add_argument("--destination", type=Path, default=ROOT / "docs/releases/validation/qa02")
    args = parser.parse_args()
    package(args.source.resolve(), args.destination.resolve())
