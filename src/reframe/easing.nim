## Cubic-bezier easing curves for smooth camera transitions
##
## Provides easing functions that transform linear time parameters into
## natural-feeling motion curves. Used for cinematic speaker tracking.

import ../tracking/types

export EasingPreset

proc lerp*(a, b: float, t: float): float =
  ## Linear interpolation between two values
  ##
  ## Args:
  ##   a: Start value
  ##   b: End value
  ##   t: Parameter in range [0, 1]
  ##
  ## Returns:
  ##   Interpolated value between a and b
  a + (b - a) * t

proc cubicBezier*(t: float, p0, p1, p2, p3: float): float =
  ## Evaluate cubic bezier curve at parameter t
  ##
  ## Standard cubic bezier formula for smooth easing curves.
  ## Used for cinematic camera motion.
  ##
  ## Args:
  ##   t: Parameter in range [0, 1]
  ##   p0, p1, p2, p3: Control points (typically 0.0, x1, x2, 1.0)
  ##
  ## Returns:
  ##   Curve value at parameter t, in range [0, 1]
  ##
  ## Example:
  ##   # ease-in-out curve
  ##   let eased = cubicBezier(0.5, 0.0, 0.42, 0.58, 1.0)

  let u = 1.0 - t
  result = u*u*u * p0 +
           3.0 * u*u * t * p1 +
           3.0 * u * t*t * p2 +
           t*t*t * p3

proc easingFunction*(t: float, preset: EasingPreset): float =
  ## Apply easing curve to linear time parameter
  ##
  ## Transforms linear time progression into natural-feeling motion.
  ## Different presets provide different feels suitable for various contexts.
  ##
  ## Args:
  ##   t: Linear time parameter in range [0, 1]
  ##   preset: Speed/feel preset (Slow, Medium, Fast)
  ##
  ## Returns:
  ##   Eased value in range [0, 1] for interpolation
  ##
  ## Presets:
  ##   Slow: Gradual acceleration/deceleration (cinematic/documentary)
  ##   Medium: Balanced ease-in-out (conversational)
  ##   Fast: Quick motion (social media/TikTok)

  case preset:
  of Slow:
    # cubic-bezier(0.0, 0.25, 0.25, 1.0)
    # Gradual acceleration and deceleration - cinematic feel
    cubicBezier(t, 0.0, 0.25, 0.25, 1.0)
  of Medium:
    # cubic-bezier(0.0, 0.42, 0.58, 1.0)
    # Balanced ease-in-out - conversational
    cubicBezier(t, 0.0, 0.42, 0.58, 1.0)
  of Fast:
    # cubic-bezier(0.0, 0.55, 1.0, 1.0)
    # Quick motion - social media energy
    cubicBezier(t, 0.0, 0.55, 1.0, 1.0)

proc getDuration*(preset: EasingPreset): float =
  ## Get transition duration in seconds for a preset
  ##
  ## Args:
  ##   preset: Speed preset (Slow, Medium, Fast)
  ##
  ## Returns:
  ##   Duration in seconds
  ##
  ## Durations:
  ##   Slow: 1.5 seconds (cinematic, professional)
  ##   Medium: 0.75 seconds (balanced, conversational)
  ##   Fast: 0.35 seconds (social media, quick)

  case preset:
  of Slow:
    1.5  # 1-2 second range, centered
  of Medium:
    0.75  # 0.5-1 second range, centered
  of Fast:
    0.35  # 0.2-0.5 second range, centered
