#!/usr/bin/env python3
"""
Export engagement markers to AAF format using pyaaf2.

AAF (Advanced Authoring Format) is supported by:
  - Avid Media Composer
  - Adobe After Effects
  - DaVinci Resolve

Usage:
    python export_aaf.py --input markers.json --output project.aaf --video video.mp4

The markers JSON format:
{
  "video": "path/to/video.mp4",
  "markers": [
    {
      "type": "engagement_peak",
      "timestamp_ms": 30000,
      "duration_ms": 1000,
      "name": "Peak #1",
      "comment": "Score: 85/100",
      "color": "#00FF00"
    }
  ]
}
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import aaf2
    from aaf2.misc import AAFCharArray
except ImportError:
    print("Error: pyaaf2 not installed. Run: pip install pyaaf2", file=sys.stderr)
    sys.exit(1)


def hex_to_rgb(hex_color: str) -> tuple:
    """Convert hex color to RGB tuple (0-65535 range for AAF)."""
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    # AAF uses 16-bit color values (0-65535)
    return (r * 257, g * 257, b * 257)


def marker_type_to_label(marker_type: str) -> str:
    """Convert marker type to display label."""
    labels = {
        "engagement_peak": "Engagement",
        "scene_boundary": "Scene",
        "speaker_change": "Speaker"
    }
    return labels.get(marker_type, "Marker")


def export_aaf(video_path: str, markers: list, output_path: str, frame_rate: float = 30.0):
    """
    Create AAF file with markers referencing the video.

    AAF markers are implemented as CommentMarkers within an EventMobSlot
    on the CompositionMob. This approach is compatible with Media Composer
    and After Effects.
    """
    with aaf2.open(output_path, 'w') as f:
        # Set up edit rate (frames per second as rational)
        edit_rate = aaf2.rational.AAFRational(int(frame_rate), 1)

        # Create MasterMob for the video source reference
        master_mob = f.create.MasterMob(Path(video_path).stem)
        f.content.mobs.append(master_mob)

        # Create CompositionMob for the timeline with markers
        comp_name = f"Engagement Analysis - {Path(video_path).stem}"
        comp_mob = f.create.CompositionMob(comp_name)
        comp_mob['AppCode'].value = 7  # Avid application code
        f.content.mobs.append(comp_mob)

        # Calculate duration based on last marker (with buffer)
        if markers:
            max_ms = max(m['timestamp_ms'] + m.get('duration_ms', 1000) for m in markers)
            duration_frames = int((max_ms / 1000.0) * frame_rate) + int(frame_rate * 10)  # +10s buffer
        else:
            duration_frames = int(frame_rate * 60)  # 1 minute default

        # Create a Filler for the timeline duration
        filler = f.create.Filler("DataDef_Sound", duration_frames)

        # Create TimelineMobSlot for the base timeline
        timeline_slot = comp_mob.create_timeline_slot(edit_rate, slot_id=1)
        timeline_slot.segment = filler

        # Create EventMobSlot for markers (using DescriptiveMarker or CommentMarker)
        # EventMobSlots hold time-positioned events like markers
        if markers:
            # Create a Sequence to hold the markers
            event_slot = comp_mob.create_event_slot(edit_rate, slot_id=1000)
            event_slot.name = "Honeyclip Markers"

            # Create Sequence for the event slot
            sequence = f.create.Sequence("DataDef_DescriptiveMetadata")

            # Add markers as DescriptiveMarker or use CommentMarker
            for i, marker in enumerate(markers):
                # Calculate position in edit units (frames)
                position = int((marker['timestamp_ms'] / 1000.0) * frame_rate)
                duration = max(1, int((marker.get('duration_ms', 1000) / 1000.0) * frame_rate))

                # Create a DescriptiveMarker
                desc_marker = f.create.DescriptiveMarker()
                desc_marker['Position'].value = position
                desc_marker['Comment'].value = f"{marker['name']}: {marker['comment']}"

                # Set color using DescriptiveMarkerStruct if available
                color = hex_to_rgb(marker.get('color', '#FFFFFF'))
                # AAF stores color in UserComments or dedicated properties

                # Add described slots reference (empty means entire composition)
                desc_marker['DescribedSlots'].value = []

                sequence.components.append(desc_marker)

            event_slot.segment = sequence

        # Add a UserComment with export info
        comp_mob['UserComments'].value = {
            'honeyclip_export': 'true',
            'marker_count': str(len(markers)),
            'source_video': video_path
        }

    print(f"Created AAF: {output_path} with {len(markers)} markers")


def export_aaf_simple(video_path: str, markers: list, output_path: str, frame_rate: float = 30.0):
    """
    Simplified AAF export using CommentMarkers on the composition.

    This approach creates markers as UserComments with position data,
    which is widely compatible across AAF-supporting applications.
    """
    with aaf2.open(output_path, 'w') as f:
        edit_rate = int(frame_rate)

        # Create source clip reference
        master_mob = f.create.MasterMob(Path(video_path).stem)
        f.content.mobs.append(master_mob)

        # Create composition
        comp_mob = f.create.CompositionMob(f"Markers - {Path(video_path).stem}")
        f.content.mobs.append(comp_mob)

        # Build marker data as comments
        marker_comments = {}
        for i, m in enumerate(markers):
            key = f"marker_{i:04d}"
            tc_sec = m['timestamp_ms'] / 1000.0
            marker_comments[key] = f"{m['name']}|{tc_sec:.3f}|{m['comment']}|{m.get('color', '#FFFFFF')}"

        # Store markers in UserComments
        marker_comments['honeyclip_marker_count'] = str(len(markers))
        marker_comments['honeyclip_source'] = video_path
        comp_mob['UserComments'].value = marker_comments

    print(f"Created AAF: {output_path} with {len(markers)} markers (simple format)")


def main():
    parser = argparse.ArgumentParser(
        description='Export engagement markers to AAF format',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python export_aaf.py --input markers.json --output project.aaf
  python export_aaf.py --input markers.json --output project.aaf --video video.mp4
  python export_aaf.py --input markers.json --output project.aaf --fps 24

Marker JSON format:
{
  "video": "path/to/video.mp4",
  "markers": [
    {
      "type": "engagement_peak",
      "timestamp_ms": 30000,
      "duration_ms": 1000,
      "name": "Peak #1",
      "comment": "Score: 85/100",
      "color": "#00FF00"
    }
  ]
}
        """
    )
    parser.add_argument('--input', '-i', required=True,
                        help='JSON file with markers')
    parser.add_argument('--output', '-o', required=True,
                        help='Output AAF file path')
    parser.add_argument('--video', '-v',
                        help='Source video path (optional, overrides JSON)')
    parser.add_argument('--fps', type=float, default=30.0,
                        help='Frame rate for timecode (default: 30)')
    parser.add_argument('--simple', action='store_true',
                        help='Use simplified marker format (more compatible)')

    args = parser.parse_args()

    # Load markers from JSON
    try:
        with open(args.input) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {args.input}: {e}", file=sys.stderr)
        sys.exit(1)

    video_path = args.video or data.get('video', 'untitled.mp4')
    markers = data.get('markers', [])

    if not markers:
        print("Warning: No markers to export", file=sys.stderr)

    # Create output directory if needed
    output_dir = Path(args.output).parent
    if output_dir and not output_dir.exists():
        output_dir.mkdir(parents=True, exist_ok=True)

    # Export AAF
    try:
        if args.simple:
            export_aaf_simple(video_path, markers, args.output, args.fps)
        else:
            export_aaf(video_path, markers, args.output, args.fps)
    except Exception as e:
        print(f"Error creating AAF: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
