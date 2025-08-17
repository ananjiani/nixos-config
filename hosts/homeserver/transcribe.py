#!/usr/bin/env python3
"""
Transcription script using faster-whisper with optional speaker diarization.
Works with GTX 1070 Ti and other Pascal GPUs via CTranslate2.
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Optional
import json

from faster_whisper import WhisperModel


def transcribe_audio(
    audio_path: str,
    model_size: str = "large-v3",
    device: str = "cuda",
    compute_type: str = "float32",  # Use float32 for GTX 1070 Ti
    language: Optional[str] = None,
    task: str = "transcribe",
    output_dir: Optional[str] = None,
    output_format: str = "txt",
    output_all: bool = False,
    diarize: bool = False,
) -> None:
    """
    Transcribe audio file using faster-whisper.

    Args:
        audio_path: Path to audio file
        model_size: Whisper model size (tiny, base, small, medium, large, large-v2, large-v3)
        device: Device to use (cuda, cpu)
        compute_type: Compute type (float32, float16, int8, int8_float32)
        language: Language code (e.g., 'en', 'es', 'fr')
        task: Task to perform (transcribe, translate)
        output_dir: Output directory for results
        output_format: Output format (txt, json, srt, vtt)
        output_all: Generate all output formats
        diarize: Whether to perform speaker diarization
    """

    print(f"Loading model {model_size} on {device} with {compute_type} precision...")

    # For GTX 1070 Ti, use float32 or int8 (not float16)
    if device == "cuda" and compute_type == "float16":
        print("Warning: GTX 1070 Ti doesn't efficiently support float16. Switching to float32.")
        compute_type = "float32"

    try:
        model = WhisperModel(
            model_size,
            device=device,
            compute_type=compute_type,
            download_root=os.path.expanduser("~/.cache/whisper"),
            cpu_threads=4,  # Number of threads for CPU operations
            num_workers=1,  # Single worker to reduce GPU memory usage
        )
    except ValueError as e:
        if "float16" in str(e) and device == "cuda":
            print("Float16 not supported on this GPU. Falling back to float32...")
            model = WhisperModel(
                model_size,
                device=device,
                compute_type="float32",
                download_root=os.path.expanduser("~/.cache/whisper"),
                cpu_threads=4,
                num_workers=1,
            )
        else:
            raise

    print(f"Transcribing {audio_path}...")

    # Transcribe
    segments, info = model.transcribe(
        audio_path,
        language=language,
        task=task,
        beam_size=5,
        best_of=5,
        patience=1,
        length_penalty=1,
        temperature=0,
        compression_ratio_threshold=2.4,
        log_prob_threshold=-1.0,
        no_speech_threshold=0.6,
        condition_on_previous_text=True,
        initial_prompt=None,
        word_timestamps=False,
        prepend_punctuations="\"'¿([{-",
        append_punctuations="\"'.。,，!！?？:：)]}、",
        vad_filter=True,
        vad_parameters=dict(
            threshold=0.5,
            min_speech_duration_ms=250,
            max_speech_duration_s=float("inf"),
            min_silence_duration_ms=2000,
            speech_pad_ms=400,
        ),
    )

    print(f"Detected language: {info.language} (probability: {info.language_probability:.2f})")

    # Process segments
    results = []
    for segment in segments:
        result = {
            "start": segment.start,
            "end": segment.end,
            "text": segment.text.strip(),
        }
        results.append(result)
        print(f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}")

    # Save output
    if output_dir:
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
    else:
        output_path = Path(audio_path).parent

    base_name = Path(audio_path).stem

    # Determine which formats to output
    formats_to_save = ["txt", "json", "srt", "vtt"] if output_all else [output_format]

    for fmt in formats_to_save:
        if fmt == "txt":
            output_file = output_path / f"{base_name}.txt"
            with open(output_file, "w", encoding="utf-8") as f:
                for result in results:
                    f.write(f"{result['text']}\n")
            print(f"Saved transcription to {output_file}")

        elif fmt == "json":
            output_file = output_path / f"{base_name}.json"
            with open(output_file, "w", encoding="utf-8") as f:
                json.dump(results, f, ensure_ascii=False, indent=2)
            print(f"Saved transcription to {output_file}")

        elif fmt == "srt":
            output_file = output_path / f"{base_name}.srt"
            with open(output_file, "w", encoding="utf-8") as f:
                for i, result in enumerate(results, 1):
                    start = format_timestamp(result["start"], fmt="srt")
                    end = format_timestamp(result["end"], fmt="srt")
                    f.write(f"{i}\n{start} --> {end}\n{result['text']}\n\n")
            print(f"Saved subtitles to {output_file}")

        elif fmt == "vtt":
            output_file = output_path / f"{base_name}.vtt"
            with open(output_file, "w", encoding="utf-8") as f:
                f.write("WEBVTT\n\n")
                for result in results:
                    start = format_timestamp(result["start"], fmt="vtt")
                    end = format_timestamp(result["end"], fmt="vtt")
                    f.write(f"{start} --> {end}\n{result['text']}\n\n")
            print(f"Saved subtitles to {output_file}")

    # Optional: Speaker diarization
    if diarize:
        print("\nPerforming speaker diarization...")
        try:
            from pyannote.audio import Pipeline

            # Use pretrained pipeline
            pipeline = Pipeline.from_pretrained(
                "pyannote/speaker-diarization-3.1",
                use_auth_token=os.getenv("HF_TOKEN"),
            )

            # Run diarization
            diarization = pipeline(audio_path)

            # Save diarization results
            diarization_file = output_path / f"{base_name}_diarization.rttm"
            with open(diarization_file, "w") as f:
                diarization.write_rttm(f)
            print(f"Saved diarization to {diarization_file}")

        except Exception as e:
            print(f"Diarization failed: {e}")
            print("You may need to set HF_TOKEN environment variable for Hugging Face access")


def format_timestamp(seconds: float, fmt: str = "srt") -> str:
    """Format timestamp for subtitle formats."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = seconds % 60

    if fmt == "srt":
        return f"{hours:02d}:{minutes:02d}:{secs:06.3f}".replace(".", ",")
    else:  # vtt
        return f"{hours:02d}:{minutes:02d}:{secs:06.3f}"


def main():
    parser = argparse.ArgumentParser(
        description="Transcribe audio using faster-whisper (GPU-accelerated for GTX 1070 Ti)"
    )
    parser.add_argument("audio", help="Path to audio file")
    parser.add_argument(
        "--model",
        default="large-v3",
        choices=["tiny", "base", "small", "medium", "large", "large-v2", "large-v3"],
        help="Model size (default: large-v3)",
    )
    parser.add_argument(
        "--device",
        default="cuda",
        choices=["cuda", "cpu"],
        help="Device to use (default: cuda)",
    )
    parser.add_argument(
        "--compute-type",
        default="float32",
        choices=["float32", "float16", "int8", "int8_float32"],
        help="Compute type (default: float32 for GTX 1070 Ti compatibility)",
    )
    parser.add_argument(
        "--language",
        help="Language code (e.g., en, es, fr). Auto-detect if not specified",
    )
    parser.add_argument(
        "--task",
        default="transcribe",
        choices=["transcribe", "translate"],
        help="Task to perform (default: transcribe)",
    )
    parser.add_argument(
        "--output-dir",
        help="Output directory (default: same as input file)",
    )
    parser.add_argument(
        "--output-format",
        default="txt",
        choices=["txt", "json", "srt", "vtt"],
        help="Output format (default: txt)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Generate all output formats (txt, json, srt, vtt)",
    )
    parser.add_argument(
        "--diarize",
        action="store_true",
        help="Perform speaker diarization (requires HF_TOKEN)",
    )

    args = parser.parse_args()

    if not Path(args.audio).exists():
        print(f"Error: File {args.audio} not found")
        sys.exit(1)

    transcribe_audio(
        args.audio,
        model_size=args.model,
        device=args.device,
        compute_type=args.compute_type.replace("-", "_"),  # Convert CLI format to function format
        language=args.language,
        task=args.task,
        output_dir=args.output_dir,
        output_format=args.output_format,
        output_all=args.all,
        diarize=args.diarize,
    )


if __name__ == "__main__":
    main()
