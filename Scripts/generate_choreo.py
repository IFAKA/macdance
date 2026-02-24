#!/usr/bin/env python3
"""
Generates choreography from an MP3 file.
Tries EDGE first; falls back to template-based generation if unavailable.
Output: choreo.json (2D normalized joint positions, same space as Apple Vision)
Progress JSON lines streamed to stdout.
"""

import sys
import json
import os
import argparse
import math
import numpy as np


JOINT_NAMES = [
    "nose", "left_eye", "right_eye", "left_ear", "right_ear",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle"
]

SMPL_TO_JOINT = {
    15: "nose",
    16: "left_ear",
    17: "right_ear",
    18: "left_shoulder",
    19: "right_shoulder",
    20: "left_elbow",
    21: "right_elbow",
    22: "left_wrist",
    23: "right_wrist",
    1: "left_hip",
    2: "right_hip",
    4: "left_knee",
    5: "right_knee",
    7: "left_ankle",
    8: "right_ankle"
}


def emit_progress(stage: str, progress: float):
    print(json.dumps({"stage": stage, "progress": progress}), flush=True)


def project_smpl_to_2d(joints_3d: np.ndarray) -> dict:
    """Projects SMPL 3D joints to normalized 2D [0,1] coordinates."""
    visible = {}
    for smpl_idx, name in SMPL_TO_JOINT.items():
        if smpl_idx < len(joints_3d):
            j = joints_3d[smpl_idx]
            visible[name] = (float(j[0]), float(j[1]))

    if not visible:
        return {}

    xs = [v[0] for v in visible.values()]
    ys = [v[1] for v in visible.values()]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    range_x = max_x - min_x or 1.0
    range_y = max_y - min_y or 1.0

    normalized = {}
    for name, (x, y) in visible.items():
        normalized[name] = [
            (x - min_x) / range_x,
            1.0 - (y - min_y) / range_y
        ]

    return normalized


def generate_template_choreo(bpm: float, beat_times: list, duration: float) -> list:
    """
    Template-based fallback choreography using librosa beat tracking.
    Sequences moves from a predefined library based on energy and beat position.
    """
    frames = []
    beat_interval = 60.0 / bpm

    # CGPoint encodes as [x, y] array in Swift's Codable
    def pt(x, y):
        return [x, y]

    def base_pose():
        return {
            "nose":           pt(0.50, 0.08),
            "left_shoulder":  pt(0.38, 0.22),
            "right_shoulder": pt(0.62, 0.22),
            "left_elbow":     pt(0.28, 0.38),
            "right_elbow":    pt(0.72, 0.38),
            "left_wrist":     pt(0.22, 0.52),
            "right_wrist":    pt(0.78, 0.52),
            "left_hip":       pt(0.42, 0.52),
            "right_hip":      pt(0.58, 0.52),
            "left_knee":      pt(0.40, 0.70),
            "right_knee":     pt(0.60, 0.70),
            "left_ankle":     pt(0.40, 0.88),
            "right_ankle":    pt(0.60, 0.88)
        }

    def arms_up(t_phase: float):
        p = base_pose()
        lift = abs(math.sin(t_phase * math.pi))
        p["left_elbow"]  = pt(0.30, 0.22 - lift * 0.10)
        p["right_elbow"] = pt(0.70, 0.22 - lift * 0.10)
        p["left_wrist"]  = pt(0.25, 0.10 - lift * 0.08)
        p["right_wrist"] = pt(0.75, 0.10 - lift * 0.08)
        return p

    def side_step(t_phase: float, direction: float = 1.0):
        p = base_pose()
        shift = direction * 0.06 * abs(math.sin(t_phase * math.pi))
        for k in p:
            p[k] = [p[k][0] + shift, p[k][1]]
        p["left_elbow"]  = pt(0.20, 0.35)
        p["right_elbow"] = pt(0.80, 0.35)
        p["left_wrist"]  = pt(0.15, 0.50)
        p["right_wrist"] = pt(0.85, 0.50)
        return p

    def wave_arms(t_phase: float):
        p = base_pose()
        wave = math.sin(t_phase * math.pi * 2)
        p["left_elbow"]  = pt(0.28 + wave * 0.08, 0.32 + wave * 0.06)
        p["left_wrist"]  = pt(0.18 + wave * 0.12, 0.20 + wave * 0.10)
        p["right_elbow"] = pt(0.72 - wave * 0.08, 0.32 - wave * 0.06)
        p["right_wrist"] = pt(0.82 - wave * 0.12, 0.20 - wave * 0.10)
        return p

    move_sequence = [arms_up, side_step, wave_arms, side_step]
    move_beats = 4

    for i, beat_time in enumerate(beat_times):
        if beat_time > duration:
            break
        move_idx = (i // move_beats) % len(move_sequence)
        beat_in_move = i % move_beats
        t_phase = beat_in_move / move_beats
        direction = 1.0 if (i // move_beats) % 2 == 0 else -1.0

        if move_sequence[move_idx] == side_step:
            joints = side_step(t_phase, direction)
        else:
            joints = move_sequence[move_idx](t_phase)

        frames.append({
            "timestamp": beat_time,
            "joints": joints
        })

    return frames


def try_edge_generation(mp3_path: str, output_dir: str, bpm: float, beat_times: list) -> list | None:
    """Attempt EDGE-based generation. Returns frames list or None if unavailable."""
    try:
        import torch
        import importlib
        edge_module = importlib.util.find_spec("EDGE")
        if edge_module is None:
            return None

        emit_progress("Loading EDGE model", 0.35)
        from EDGE import EDGE
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        model = EDGE(device=device)

        emit_progress("Running EDGE inference", 0.5)
        output = model.generate(mp3_path)

        emit_progress("Projecting to 2D", 0.75)
        frames = []
        for i, (t, pose_3d) in enumerate(output):
            joints_2d = project_smpl_to_2d(np.array(pose_3d))
            if joints_2d:
                frames.append({"timestamp": float(t), "joints": joints_2d})

        return frames if frames else None

    except Exception:
        return None


def generate(mp3_path: str, output_dir: str):
    os.makedirs(output_dir, exist_ok=True)

    emit_progress("Analyzing music", 0.1)

    try:
        import librosa
        y, sr = librosa.load(mp3_path, sr=None, mono=True)
        duration = librosa.get_duration(y=y, sr=sr)
        tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
        beat_times = librosa.frames_to_time(beat_frames, sr=sr).tolist()
        bpm = float(np.atleast_1d(tempo)[0])
        if not beat_times:
            beat_interval = 60.0 / bpm
            beat_times = [i * beat_interval for i in range(int(duration / beat_interval))]
    except Exception as e:
        emit_progress("Analyzing music (fallback)", 0.15)
        try:
            import soundfile as sf_fallback
            info = sf_fallback.info(mp3_path)
            duration = info.duration
        except Exception:
            duration = 180.0
        bpm = 120.0
        beat_interval = 60.0 / bpm
        beat_times = [i * beat_interval for i in range(int(duration / beat_interval))]

    analysis = {
        "bpm": bpm,
        "duration": duration,
        "beat_times": beat_times
    }
    with open(os.path.join(output_dir, "analysis.json"), "w") as f:
        json.dump(analysis, f)

    emit_progress("Generating moves", 0.3)

    frames = try_edge_generation(mp3_path, output_dir, bpm, beat_times)

    if frames is None:
        emit_progress("Generating moves (template mode)", 0.4)
        frames = generate_template_choreo(bpm, beat_times, duration)

    emit_progress("Saving choreography", 0.9)

    choreo = {
        "songMD5": os.path.basename(output_dir),
        "bpm": bpm,
        "totalDuration": duration,
        "frames": frames
    }

    with open(os.path.join(output_dir, "choreo.json"), "w") as f:
        json.dump(choreo, f)

    emit_progress("Done", 1.0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate dance choreography from an MP3 file")
    parser.add_argument("command", nargs="?", default="generate", choices=["generate"],
                        help="Command to run (default: generate)")
    parser.add_argument("--mp3", required=True, help="Path to input MP3/M4A file")
    parser.add_argument("--output", required=True, help="Output directory for choreo.json and analysis.json")
    args = parser.parse_args()

    if not os.path.isfile(args.mp3):
        print(json.dumps({"stage": "Error", "progress": 0, "error": f"File not found: {args.mp3}"}), flush=True)
        sys.exit(1)

    try:
        generate(args.mp3, args.output)
    except Exception as e:
        print(json.dumps({"stage": "Error", "progress": 0, "error": str(e)}), flush=True)
        sys.exit(1)
