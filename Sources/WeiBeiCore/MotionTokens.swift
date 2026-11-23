// Generated from DesignSystem/08-implementation/tokens.json.

public enum WeiBeiMotionTokens {
    public struct Cubic: Sendable {
        public let x1: Double
        public let y1: Double
        public let x2: Double
        public let y2: Double
    }

    public static let easeOut = Cubic(x1: 0, y1: 0, x2: 0.58, y2: 1)
    public static let easeOutStrong = Cubic(x1: 0.22, y1: 1, x2: 0.36, y2: 1)
    public static let easeIn = Cubic(x1: 0.42, y1: 0, x2: 1, y2: 1)
    public static let easeInOut = Cubic(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    public static let easeOvershoot = Cubic(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1)

    public static let durationControl = 0.12
    public static let durationSm = 0.2
    public static let durationMd = 0.32
    public static let durationLg = 0.42
    public static let durationSmExit = 0.15
    public static let durationMdExit = 0.25
    public static let durationLgExit = 0.35

    public static let css = """
    :root {
      --ease-out: cubic-bezier(0, 0, 0.58, 1);
      --ease-out-strong: cubic-bezier(0.22, 1, 0.36, 1);
      --ease-in: cubic-bezier(0.42, 0, 1, 1);
      --ease-in-out: cubic-bezier(0.42, 0, 0.58, 1);
      --ease-overshoot: cubic-bezier(0.34, 1.56, 0.64, 1);
      --ease-spring: var(--ease-out-strong);
      --duration-control: 120ms;
      --duration-sm: 200ms;
      --duration-md: 320ms;
      --duration-lg: 420ms;
      --duration-sm-exit: 150ms;
      --duration-md-exit: 250ms;
      --duration-lg-exit: 350ms;
    }

    @supports (animation-timing-function: linear(0, 1)) {
      :root { --ease-spring: linear(0, 0.32, 0.78, 1.04, 1.09, 1.06, 1.02, 1, 0.99, 0.99, 1); }
    }
    """
}
