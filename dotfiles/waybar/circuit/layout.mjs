// Definitions of the waybar boxes and the wiring between them. build.mjs checks the rules and writes the wiring for style.css and the clock ring (pkgs/clock-ring).
// The wiring is styled after circuit board traces. Coordinates are px with each module's top left as the origin, y pointing down.

export const BAR_WIDTH = 52;
// px kept between lines and boxes, and between parallel lines
export const CLEARANCE = 3;
export const SPACING = 4;

// Rules shown in the preview. These are what build.mjs checks
export const RULES = [
  "Lines are made only of 1px horizontal and vertical segments, turning at right angles.",
  "Lines end by meeting a box side perpendicularly. Contact points are only at path ends, at least 3px from box corners. Lines do not branch.",
  `Lines never pass inside or behind boxes. Keep at least ${CLEARANCE}px from boxes and ${SPACING}px from other lines. Lines do not cross.`,
  "Lines connect not only adjacent boxes but also distant ones, passing along the open side of the boxes in between. The left and right edges of the bar (x=0 and x=51) are lanes for long lines.",
  "Module boundaries are crossed with vertical segments. The boundary between the clock ring and the bar is crossed with a horizontal segment.",
  "Lines that connect to nothing fade out along their extended last segment. Lines reaching the screen edge leave the screen without fading.",
  "Lines enter the clock ring only at its four compass points, heading toward the center.",
];

// A contact point with a box at the end of a path. side is a box side (top, bottom, left, right) or a circle bearing (n, e, s, w).
// at is the position along the side: x for top and bottom, y for left and right
const pin = (side, at) => ({ pin: side, at });
// A contact point on the top edge of the box right below the module that it does not draw itself (tray)
const below = (at) => ({ below: at });

// The two lines on the left and right edges of the bar that pass straight through the workspaces
const edgeLanes = [{ path: [[0, 0], [0, 27]] }, { path: [[51, 0], [51, 27]] }];

// box is [left, top, side length]. h is the module height.
// A trace's path is a list of contact points or [x, y] points. Lines with fade fade out along their last segment.
// Boxes zigzag left and right, so left-leaning boxes connect through the open space left of a right box, and right-leaning boxes through the space right of a left box
export const modules = {
  overview: {
    selector: "#custom-overview",
    h: 54,
    box: [20, 18, 28],
    traces: [
      // Two lines exiting through the top of the screen
      { path: [pin("top", 30), [30, 0]] },
      { path: [pin("top", 38), [38, 0]] },
      // Exits through the left edge and, on QHD, enters the clock ring's north point
      { path: [pin("left", 24), [8, 24], [8, 4], [0, 4]] },
      // To the first workspace
      { path: [pin("bottom", 24), [24, 49], [20, 49], [20, 53]] },
      // Down the left edge to cpu
      { path: [pin("left", 40), [0, 40], [0, 53]] },
      // Down the right edge to memory
      { path: [pin("right", 30), [51, 30], [51, 53]] },
    ],
  },

  // Workspaces cycle left, right, middle in threes. From the last workspace, the line goes to x=20 on cpu's top edge instead of the next one
  ws1: {
    selector: "#workspaces button:nth-child(3n+1)",
    h: 28,
    box: [4, 4, 20],
    traces: [
      ...edgeLanes,
      { path: [[20, 0], pin("top", 20)] },
      // Out of the right side to x=32 on the top edge of the next workspace, placed on the right
      { path: [pin("right", 14), [32, 14], [32, 27]] },
    ],
  },
  ws1Last: {
    selector: "#workspaces button:nth-child(3n+1):last-child",
    h: 28,
    box: [4, 4, 20],
    traces: [...edgeLanes, { path: [[20, 0], pin("top", 20)] }, { path: [pin("bottom", 20), [20, 27]] }],
  },
  ws2: {
    selector: "#workspaces button:nth-child(3n+2)",
    h: 28,
    box: [28, 4, 20],
    traces: [...edgeLanes, { path: [[32, 0], pin("top", 32)] }, { path: [pin("bottom", 32), [32, 27]] }],
  },
  ws2Last: {
    selector: "#workspaces button:nth-child(3n+2):last-child",
    h: 28,
    box: [28, 4, 20],
    traces: [
      ...edgeLanes,
      { path: [[32, 0], pin("top", 32)] },
      // Out of the left side to x=20 on cpu's top edge
      { path: [pin("left", 14), [20, 14], [20, 27]] },
    ],
  },
  // A middle workspace drops to x=20 whether the next is a left workspace or cpu, so the last case is not special
  ws3: {
    selector: "#workspaces button:nth-child(3n)",
    h: 28,
    box: [16, 4, 20],
    traces: [...edgeLanes, { path: [[32, 0], pin("top", 32)] }, { path: [pin("bottom", 20), [20, 27]] }],
  },

  cpu: {
    selector: "#cpu",
    h: 42,
    box: [4, 6, 30],
    traces: [
      { path: [[20, 0], pin("top", 20)] },
      { path: [[0, 0], [0, 14], pin("left", 14)] },
      { path: [[51, 0], [51, 41]] },
      // To memory
      { path: [pin("right", 20), [40, 20], [40, 41]] },
      // Left of memory to idle
      { path: [pin("bottom", 10), [10, 41]] },
    ],
  },
  memory: {
    selector: "#memory",
    h: 42,
    box: [14, 4, 30],
    traces: [
      { path: [[40, 0], pin("top", 40)] },
      { path: [[51, 0], [51, 18], pin("right", 18)] },
      { path: [[10, 0], [10, 41]] },
      // To idle
      { path: [pin("bottom", 18), [18, 41]] },
      // Right of idle to pulseaudio
      { path: [pin("bottom", 38), [38, 41]] },
    ],
  },
  idle: {
    selector: "#idle_inhibitor",
    h: 36,
    box: [6, 6, 24],
    traces: [
      { path: [[10, 0], pin("top", 10)] },
      { path: [[18, 0], pin("top", 18)] },
      { path: [[38, 0], [38, 35]] },
      // To pulseaudio
      { path: [pin("right", 18), [34, 18], [34, 35]] },
      // Left of pulseaudio to clock
      { path: [pin("bottom", 10), [10, 35]] },
      // Down the left edge to the notifications
      { path: [pin("left", 20), [0, 20], [0, 35]] },
    ],
  },
  pulseaudio: {
    selector: "#pulseaudio",
    h: 42,
    box: [18, 6, 30],
    traces: [
      { path: [[34, 0], pin("top", 34)] },
      { path: [[38, 0], pin("top", 38)] },
      { path: [[0, 0], [0, 41]] },
      { path: [[10, 0], [10, 41]] },
      // To clock
      { path: [pin("left", 20), [14, 20], [14, 41]] },
      // Down the right edge, passing right of clock and the notifications
      { path: [pin("right", 20), [51, 20], [51, 41]] },
    ],
  },
  clock: {
    selector: "#clock",
    h: 50,
    box: [4, 6, 36],
    traces: [
      { path: [[10, 0], pin("top", 10)] },
      { path: [[14, 0], pin("top", 14)] },
      { path: [[0, 0], [0, 49]] },
      { path: [[51, 0], [51, 49]] },
      // To the notifications
      { path: [pin("bottom", 14), [14, 49]] },
      // Right of the notifications. On QHD, to the tray
      { path: [pin("right", 20), [44, 20], [44, 49]] },
    ],
  },
  // On the 4K bar the notifications come last, so lines going down fade out
  notification: {
    selector: "#custom-notification",
    h: 44,
    box: [6, 6, 30],
    traces: [
      { path: [[14, 0], pin("top", 14)] },
      { path: [[0, 0], [0, 20], pin("left", 20)] },
      { path: [[44, 0], [44, 43]], fade: true },
      { path: [[51, 0], [51, 43]], fade: true },
      { path: [pin("bottom", 22), [22, 43]], fade: true },
    ],
  },
  // On the QHD bar the tray follows the notifications, so the lines at x=22 and x=44 enter the tray's top edge
  notificationRight: {
    selector: "window#waybar.right #custom-notification",
    h: 44,
    box: [6, 6, 30],
    traces: [
      { path: [[14, 0], pin("top", 14)] },
      { path: [[0, 0], [0, 20], pin("left", 20)] },
      { path: [[44, 0], below(44)] },
      { path: [[51, 0], [51, 43]], fade: true },
      { path: [pin("bottom", 22), below(22)] },
    ],
  },
  // The power box sits at the bottom of the bar, apart from the other boxes. The two lines going up fade out and the one below exits through the bottom of the screen
  power: {
    selector: "#custom-power",
    h: 100,
    box: [18, 56, 30],
    traces: [
      { path: [pin("top", 36), [36, 0]], fade: true },
      { path: [pin("left", 70), [8, 70], [8, 20]], fade: true },
      { path: [pin("bottom", 28), [28, 99]] },
    ],
  },
};

// Left and right edges of the tray box, used to keep top-edge contact points away from corners
export const tray = { left: 18, right: 47 };

// The clock ring at the top right of the QHD monitor. Sizes match the constants in clock-ring.py.
// The window's right edge touches the vertical bar's left edge, so the line exiting left of overview comes straight in
export const ring = {
  w: 222,
  h: 212,
  cx: 135,
  cy: 87,
  r: 75,
  traces: [
    // Comes from overview and enters the north point at the top, where no spectrum is drawn
    { path: [[221, 4], [135, 4], pin("n")] },
    // Exits left, turns down, and fades out as it extends downward
    { path: [pin("w"), [20, 87], [20, 211]], fade: true },
    { path: [pin("s"), [135, 211]], fade: true },
  ],
};

// Pairs of modules that can be stacked vertically. Checks that line positions match at the upper one's bottom and the lower one's top
export const stacks = [
  ["overview", "ws1"],
  ["overview", "ws1Last"],
  ["ws1", "ws2"],
  ["ws1", "ws2Last"],
  ["ws2", "ws3"],
  ["ws3", "ws1"],
  ["ws3", "ws1Last"],
  ["ws1Last", "cpu"],
  ["ws2Last", "cpu"],
  ["ws3", "cpu"],
  ["cpu", "memory"],
  ["memory", "idle"],
  ["idle", "pulseaudio"],
  ["pulseaudio", "clock"],
  ["clock", "notification"],
  ["clock", "notificationRight"],
];

// Box border and fill colors per workspace state. Line colors do not change
export const workspaceStates = [
  { selector: "#workspaces button", edge: "@wire", glass: "alpha(@bg1, 0.45)" },
  { selector: "#workspaces button:hover", edge: "@edge", glass: "alpha(@bg1, 0.45)" },
  // The workspace shown on that monitor
  { selector: "#workspaces button.active", edge: "@edge-hi", glass: "@glass" },
  // The workspace shown on the focused monitor
  { selector: "#workspaces button.focused", edge: "@blue", glass: "alpha(@blue, 0.3)" },
  { selector: "#workspaces button.urgent", edge: "@red", glass: "@glass" },
];
