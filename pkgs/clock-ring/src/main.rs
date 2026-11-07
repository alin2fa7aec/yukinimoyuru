// Wall clock. Stacks the hour and minute in two rows inside a circle, and draws the spectrum of the playing audio radially inward from the rim.
// waybar's CSS cannot arrange things in a circle, so this draws its own transparent wlr-layer-shell surface.
// It renders with cairo into shared-memory buffers and talks to the compositor directly, without a GUI toolkit,
// so a frame costs little more than the drawing itself.
// The spectrum is read from cava's raw output (one frame is BARS bytes, each 0-255).
// The top, where lines from the vertical bar come in, is left empty; bars span the 240 degrees from 10 o'clock around through 6 to 2 o'clock.
// The left and right channels go on the left and right of the circle, with bass at the bottom and treble at the top.

use std::collections::HashMap;
use std::f64::consts::PI;
use std::fs::File;
use std::io::Read;
use std::os::fd::OwnedFd;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use cairo::{Context, Format, ImageSurface, LineCap, Operator};
use smithay_client_toolkit::compositor::{CompositorHandler, CompositorState, FrameCallbackData, Region};
use smithay_client_toolkit::output::{OutputHandler, OutputState};
use smithay_client_toolkit::reexports::calloop::generic::Generic;
use smithay_client_toolkit::reexports::calloop::timer::{TimeoutAction, Timer};
use smithay_client_toolkit::reexports::calloop::{EventLoop, Interest, Mode, PostAction};
use smithay_client_toolkit::reexports::calloop_wayland_source::WaylandSource;
use smithay_client_toolkit::reexports::client::globals::registry_queue_init;
use smithay_client_toolkit::reexports::client::protocol::{wl_output, wl_shm, wl_surface};
use smithay_client_toolkit::reexports::client::{Connection, QueueHandle};
use smithay_client_toolkit::registry::{ProvidesRegistryState, RegistryState};
use smithay_client_toolkit::shell::WaylandSurface;
use smithay_client_toolkit::shell::wlr_layer::{
    Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure,
};
use smithay_client_toolkit::shm::slot::{Buffer, SlotPool};
use smithay_client_toolkit::shm::{Shm, ShmHandler};
use smithay_client_toolkit::{delegate_dispatch2, delegate_registry, registry_handlers};

const FONT: &str = "Moralerspace Argon HW";
const FONT_SIZE: f64 = 52.0;
// Place 48 bars over 240 degrees, the same spacing as the former 72 bars over 360 degrees
const BARS: usize = 48;
const ARC_START: f64 = 300.0 * PI / 180.0;
const ARC_SPAN: f64 = 240.0 * PI / 180.0;
// The gap from the rim to the base of the bars, and the maximum bar length
const BAR_GAP: f64 = 4.0;
const BAR_MAX: f64 = 30.0;
// cava stops writing after sleep_timer seconds of silence. Clear the last frame once it is this old
const STALE: Duration = Duration::from_millis(500);

const CAVA_CONFIG: &str = "
[general]
framerate = 60
bars = 48
autosens = 1
sleep_timer = 3

[input]
method = pipewire
source = auto

[output]
method = raw
channels = stereo
raw_target = /dev/stdout
data_format = binary
bit_format = 8bit

[smoothing]
noise_reduction = 77
";

type Rgb = (f64, f64, f64);

struct Palette {
    bg1: Rgb,
    fg1: Rgb,
    cyan: Rgb,
}

// The clock's geometry and wiring, written by waybar/circuit/build.mjs in dotfiles.
// The size, center and radius come from there too, so the wiring always meets the circle
#[derive(serde::Deserialize)]
struct Wires {
    size: [i32; 2],
    center: [f64; 2],
    radius: f64,
    // x, y and the opacity used in fading segments
    wires: Vec<(i32, i32, f64)>,
}

type Error = Box<dyn std::error::Error>;

fn fail(msg: impl std::fmt::Display) -> ! {
    eprintln!("clock-ring: {msg}");
    std::process::exit(1);
}

/// Read the "@define-color name #rrggbb;" lines of nordfox.css
fn load_palette(path: &str) -> Result<Palette, Error> {
    let css = std::fs::read_to_string(path)?;
    let mut colors = HashMap::new();
    for line in css.lines() {
        let Some(rest) = line.trim().strip_prefix("@define-color ") else { continue };
        let Some((name, value)) = rest.trim_end_matches(';').split_once(" #") else { continue };
        if value.len() != 6 {
            continue;
        }
        let channel = |i: usize| u8::from_str_radix(&value[i..i + 2], 16).map(|v| f64::from(v) / 255.0);
        colors.insert(name.to_string(), (channel(0)?, channel(2)?, channel(4)?));
    }
    let get = |name: &str| colors.get(name).copied().ok_or_else(|| format!("{path} has no color {name}"));
    Ok(Palette { bg1: get("bg1")?, fg1: get("fg1")?, cyan: get("cyan")? })
}

fn load_wires(path: &str) -> Result<Wires, Error> {
    let wires: Wires = serde_json::from_reader(File::open(path)?)?;
    let [w, h] = wires.size;
    if w <= 0 || h <= 0 || wires.radius <= 0.0 {
        return Err(format!("{path} has an empty size or radius").into());
    }
    Ok(wires)
}

fn local_time() -> libc::tm {
    // SAFETY: localtime_r only writes into the tm we pass
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        tm
    }
}

/// The parts of the picture that change at most once a minute, drawn ahead into their own surfaces.
/// The bars are drawn between them, so they cannot be one surface
struct Layers {
    scale: i32,
    minute: i32,
    // The wiring and the glass circle
    back: ImageSurface,
    // The hour and minute
    time: ImageSurface,
}

fn surface(wires: &Wires, scale: i32) -> Result<(ImageSurface, Context), Error> {
    let surface = ImageSurface::create(Format::ARgb32, wires.size[0] * scale, wires.size[1] * scale)?;
    let cr = Context::new(&surface)?;
    cr.scale(f64::from(scale), f64::from(scale));
    Ok((surface, cr))
}

impl Layers {
    fn new(palette: &Palette, wires: &Wires, scale: i32, tm: &libc::tm) -> Result<Layers, Error> {
        let ([cx, cy], radius) = (wires.center, wires.radius);
        let (back, cr) = surface(wires, scale)?;
        let (r, g, b) = palette.fg1;
        // Wiring is drawn pixel by pixel
        for &(x, y, a) in &wires.wires {
            cr.rectangle(f64::from(x), f64::from(y), 1.0, 1.0);
            cr.set_source_rgba(r, g, b, 0.3 * a);
            cr.fill()?;
        }
        cr.arc(cx, cy, radius, 0.0, 2.0 * PI);
        let (r, g, b) = palette.bg1;
        cr.set_source_rgba(r, g, b, 0.6);
        cr.fill()?;
        cr.arc(cx, cy, radius - 0.5, 0.0, 2.0 * PI);
        let (r, g, b) = palette.fg1;
        cr.set_source_rgba(r, g, b, 0.4);
        cr.set_line_width(1.0);
        cr.stroke()?;
        drop(cr);

        // Stack the hour shifted half a character left and the minute half a character right. The minute is cyan, as an accent in place of a colon
        let (time, cr) = surface(wires, scale)?;
        let mut font = pango::FontDescription::from_string(FONT);
        font.set_absolute_size(FONT_SIZE * f64::from(pango::SCALE));
        let half = FONT_SIZE * 0.25;
        for (value, color, ox, oy) in [(tm.tm_hour, palette.fg1, -half, -0.42), (tm.tm_min, palette.cyan, half, 0.42)] {
            let layout = pangocairo::functions::create_layout(&cr);
            layout.set_font_description(Some(&font));
            layout.set_text(&format!("{value:02}"));
            let (ink, _) = layout.pixel_extents();
            let x = cx + ox - f64::from(ink.x()) - f64::from(ink.width()) / 2.0;
            let y = cy + oy * FONT_SIZE - f64::from(ink.y()) - f64::from(ink.height()) / 2.0;
            cr.move_to(x, y + 1.0);
            cr.set_source_rgba(0.0, 0.0, 0.0, 0.6);
            pangocairo::functions::show_layout(&cr, &layout);
            cr.move_to(x, y);
            cr.set_source_rgb(color.0, color.1, color.2);
            pangocairo::functions::show_layout(&cr, &layout);
        }
        drop(cr);

        Ok(Layers { scale, minute: tm.tm_min, back, time })
    }
}

/// Draw one frame into target. bars is a sequence of 0-255 values; if empty, only the circle and time are drawn
fn paint(target: &ImageSurface, layers: &Layers, palette: &Palette, wires: &Wires, bars: &[u8]) -> Result<(), Error> {
    let cr = Context::new(target)?;
    cr.set_operator(Operator::Source);
    cr.set_source_surface(&layers.back, 0.0, 0.0)?;
    cr.paint()?;
    cr.set_operator(Operator::Over);

    // cava's stereo output runs from left treble to bass, then right bass to treble.
    // Placing it counterclockwise from 10 o'clock puts left treble at 10, the basses meeting at 6, and right treble at 2.
    // The bars lie beneath the time, so make them slightly faint to keep the text readable
    cr.save()?;
    cr.scale(f64::from(layers.scale), f64::from(layers.scale));
    cr.set_line_width(3.0);
    cr.set_line_cap(LineCap::Round);
    let (r, g, b) = palette.cyan;
    cr.set_source_rgba(r, g, b, 0.7);
    let ([cx, cy], radius) = (wires.center, wires.radius);
    let n = bars.len() as f64;
    for (i, &v) in bars.iter().enumerate() {
        if v == 0 {
            continue;
        }
        // Angles are measured clockwise with straight up as 0
        let a = ARC_START - (i as f64 + 0.5) / n * ARC_SPAN;
        let (dx, dy) = (a.sin(), -a.cos());
        let r0 = radius - BAR_GAP;
        let r1 = r0 - f64::from(v) / 255.0 * BAR_MAX;
        cr.move_to(cx + dx * r0, cy + dy * r0);
        cr.line_to(cx + dx * r1, cy + dy * r1);
    }
    cr.stroke()?;
    cr.restore()?;

    cr.set_source_surface(&layers.time, 0.0, 0.0)?;
    cr.paint()?;
    Ok(())
}

struct App {
    registry_state: RegistryState,
    output_state: OutputState,
    shm: Shm,
    qh: QueueHandle<App>,
    layer: Option<LayerSurface>,
    pool: SlotPool,
    buffer: Option<Buffer>,
    palette: Palette,
    wires: Wires,
    layers: Layers,
    frame: ImageSurface,
    bars: Vec<u8>,
    cava_buf: Vec<u8>,
    last_frame: Instant,
    scale: i32,
    configured: bool,
    // A frame callback is outstanding, so the compositor has not shown the last frame yet
    frame_pending: bool,
    // Something changed since the last frame
    dirty: bool,
}

impl App {
    fn request_draw(&mut self) {
        self.dirty = true;
        if self.configured && !self.frame_pending {
            if let Err(e) = self.draw() {
                fail(format!("drawing failed: {e}"));
            }
        }
    }

    fn draw(&mut self) -> Result<(), Error> {
        let tm = local_time();
        if self.layers.scale != self.scale || self.layers.minute != tm.tm_min {
            self.layers = Layers::new(&self.palette, &self.wires, self.scale, &tm)?;
        }
        let [width, height] = self.wires.size.map(|n| n * self.scale);
        if self.frame.width() != width {
            self.frame = ImageSurface::create(Format::ARgb32, width, height)?;
        }
        paint(&self.frame, &self.layers, &self.palette, &self.wires, &self.bars)?;
        self.frame.flush();

        // Reuse the last buffer unless the compositor still holds it or the size changed
        let stride = self.frame.stride();
        let reusable = match &self.buffer {
            Some(b) => b.height() == height && b.stride() == stride && b.canvas(&mut self.pool).is_some(),
            None => false,
        };
        if !reusable {
            let (buffer, _) = self.pool.create_buffer(width, height, stride, wl_shm::Format::Argb8888)?;
            self.buffer = Some(buffer);
        }
        let buffer = self.buffer.as_ref().expect("buffer was just set");
        let canvas = buffer.canvas(&mut self.pool).expect("buffer is free");
        // cairo's ARGB32 and wl_shm's ARGB8888 are both premultiplied, native-endian 32-bit pixels, so copy as is
        self.frame.with_data(|data| canvas.copy_from_slice(data))?;

        let layer = self.layer.as_ref().expect("layer surface exists once configured");
        let wl_surface = layer.wl_surface();
        wl_surface.damage_buffer(0, 0, width, height);
        wl_surface.frame(&self.qh, FrameCallbackData(wl_surface.clone()));
        buffer.attach_to(wl_surface)?;
        layer.commit();
        self.frame_pending = true;
        self.dirty = false;
        Ok(())
    }

    /// Take in what cava wrote. Returns false once cava has exited
    fn read_cava(&mut self, out: &File) -> bool {
        let mut chunk = [0u8; 65536];
        let n = match (&*out).read(&mut chunk) {
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => return true,
            Err(_) => 0,
        };
        if n == 0 {
            return false;
        }
        self.cava_buf.extend_from_slice(&chunk[..n]);
        let full = self.cava_buf.len() / BARS * BARS;
        if full > 0 {
            self.bars = self.cava_buf[full - BARS..full].to_vec();
            self.cava_buf.drain(..full);
            self.last_frame = Instant::now();
            self.request_draw();
        }
        true
    }

    /// Runs every second. During silence cava stops and no frames arrive, so redraw here when the minute changes or the last bars are stale
    fn tick(&mut self) {
        let stale = !self.bars.is_empty() && self.last_frame.elapsed() > STALE;
        if stale {
            self.bars.clear();
        }
        if stale || local_time().tm_min != self.layers.minute {
            self.request_draw();
        }
    }
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &wl_surface::WlSurface, factor: i32) {
        if factor != self.scale {
            self.scale = factor;
            surface.set_buffer_scale(factor);
            self.request_draw();
        }
    }

    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: wl_output::Transform) {}

    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: u32) {
        self.frame_pending = false;
        if self.dirty {
            self.request_draw();
        }
    }

    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}

    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.output_state
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}

    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}

    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
}

impl LayerShellHandler for App {
    // The compositor closes the surface when its output goes away. Exit as a failure and let systemd restart it
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &LayerSurface) {
        fail("the layer surface was closed");
    }

    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &LayerSurface, _: LayerSurfaceConfigure, _: u32) {
        if !self.configured {
            self.configured = true;
            self.request_draw();
        }
    }
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

impl ProvidesRegistryState for App {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry_state
    }
    registry_handlers![OutputState];
}

delegate_registry!(App);
delegate_dispatch2!(App);

struct Args {
    output: String,
    theme: String,
    wires: String,
    margin_right: i32,
    preview: Option<String>,
}

const USAGE: &str = "usage: clock-ring --output NAME --theme nordfox.css --wires wires.json [--margin-right PX] [--preview out.png]

  --output        output name of the monitor to show the clock on (e.g. DP-3)
  --theme         path to nordfox.css
  --wires         path to the wiring pixels (wires.json)
  --margin-right  gap between the clock and the right edge of the screen
  --preview       draw a state with audio to a PNG and exit without connecting to the compositor";

fn parse_args() -> Args {
    let mut args = std::env::args().skip(1);
    let (mut output, mut theme, mut wires, mut margin_right, mut preview) = (None, None, None, 0, None);
    while let Some(flag) = args.next() {
        let mut value = || args.next().unwrap_or_else(|| fail(format!("{flag} needs a value\n\n{USAGE}")));
        match flag.as_str() {
            "--output" => output = Some(value()),
            "--theme" => theme = Some(value()),
            "--wires" => wires = Some(value()),
            "--margin-right" => margin_right = value().parse().unwrap_or_else(|e| fail(format!("--margin-right: {e}"))),
            "--preview" => preview = Some(value()),
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            _ => fail(format!("unknown argument {flag}\n\n{USAGE}")),
        }
    }
    let theme = theme.unwrap_or_else(|| fail(format!("--theme is required\n\n{USAGE}")));
    let wires = wires.unwrap_or_else(|| fail(format!("--wires is required\n\n{USAGE}")));
    let output = match (output, &preview) {
        (Some(o), _) => o,
        (None, Some(_)) => String::new(),
        (None, None) => fail(format!("--output is required\n\n{USAGE}")),
    };
    Args { output, theme, wires, margin_right, preview }
}

fn preview(palette: &Palette, wires: &Wires, path: &str) -> Result<(), Error> {
    let bars: Vec<u8> = (0..BARS)
        .map(|i| {
            let i = i as f64;
            (255.0 * (i * 0.37).sin().abs() * (1.0 - (i - BARS as f64 / 2.0).abs() / BARS as f64)) as u8
        })
        .collect();
    let layers = Layers::new(palette, wires, 1, &local_time())?;
    let target = ImageSurface::create(Format::ARgb32, wires.size[0], wires.size[1])?;
    paint(&target, &layers, palette, wires, &bars)?;
    target.write_to_png(&mut File::create(path)?)?;
    Ok(())
}

fn run(args: Args, palette: Palette, wires: Wires) -> Result<(), Error> {
    let conn = Connection::connect_to_env()?;
    let (globals, mut queue) = registry_queue_init::<App>(&conn)?;
    let qh = queue.handle();
    let compositor = CompositorState::bind(&globals, &qh)?;
    let layer_shell = LayerShell::bind(&globals, &qh)?;
    let shm = Shm::bind(&globals, &qh)?;
    let [width, height] = wires.size;
    let pool = SlotPool::new((width * height * 4) as usize, &shm)?;
    let tm = local_time();

    let mut app = App {
        registry_state: RegistryState::new(&globals),
        output_state: OutputState::new(&globals, &qh),
        shm,
        qh: qh.clone(),
        layer: None,
        pool,
        buffer: None,
        layers: Layers::new(&palette, &wires, 1, &tm)?,
        frame: ImageSurface::create(Format::ARgb32, width, height)?,
        palette,
        wires,
        bars: Vec::new(),
        cava_buf: Vec::new(),
        last_frame: Instant::now(),
        scale: 1,
        configured: false,
        frame_pending: false,
        dirty: false,
    };

    // Output names arrive after the globals, so wait for them before picking the monitor
    queue.roundtrip(&mut app)?;
    queue.roundtrip(&mut app)?;
    let output = app
        .output_state
        .outputs()
        .find(|o| app.output_state.info(o).and_then(|i| i.name).as_deref() == Some(args.output.as_str()))
        .ok_or_else(|| format!("output {} not found", args.output))?;

    let wl_surface = compositor.create_surface(&qh);
    // Empty the input region so clicks pass through to the window below
    let region = Region::new(&compositor)?;
    wl_surface.set_input_region(Some(region.wl_region()));
    let layer = layer_shell.create_layer_surface(&qh, wl_surface, Layer::Overlay, Some("clock-ring"), Some(&output));
    // Like the vertical bar, always on top without reserving space
    layer.set_anchor(Anchor::TOP | Anchor::RIGHT);
    layer.set_margin(0, args.margin_right, 0, 0);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::None);
    layer.set_size(width as u32, height as u32);
    layer.commit();
    app.layer = Some(layer);

    let mut event_loop = EventLoop::<App>::try_new()?;
    let handle = event_loop.handle();
    WaylandSource::new(conn, queue).insert(handle.clone()).map_err(|e| e.error)?;

    let config = std::env::var_os("XDG_RUNTIME_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("clock-ring-cava.conf");
    std::fs::write(&config, CAVA_CONFIG)?;
    let mut cava = Command::new("cava").arg("-p").arg(&config).stdout(Stdio::piped()).spawn()?;
    let out = File::from(OwnedFd::from(cava.stdout.take().expect("stdout is piped")));
    handle
        .insert_source(Generic::new(out, Interest::READ, Mode::Level), |_, out, app| {
            if !app.read_cava(out) {
                // If cava dies, exit the clock too and let systemd restart it
                fail("cava exited");
            }
            Ok(PostAction::Continue)
        })
        .map_err(|e| e.error)?;
    handle
        .insert_source(Timer::from_duration(Duration::from_secs(1)), |_, _, app| {
            app.tick();
            TimeoutAction::ToDuration(Duration::from_secs(1))
        })
        .map_err(|e| e.error)?;

    event_loop.run(None, &mut app, |_| {})?;
    Ok(())
}

fn main() {
    let args = parse_args();
    let palette = load_palette(&args.theme).unwrap_or_else(|e| fail(e));
    let wires = load_wires(&args.wires).unwrap_or_else(|e| fail(e));
    let result = match &args.preview {
        Some(path) => preview(&palette, &wires, path),
        None => run(args, palette, wires),
    };
    if let Err(e) = result {
        fail(e);
    }
}
