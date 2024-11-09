const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

pub const egl = @cImport({
    @cInclude("EGL/wayland-egl.h");
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
});

pub const Zeichnung = struct {
    allocator: std.mem.Allocator = undefined,
    display: *wl.Display = undefined,
    registry: *wl.Registry = undefined,
    seat: ?*wl.Seat = null,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    shm_supported_formats: std.ArrayList(wl.Shm.Format),
    xdg_wm_base: ?*xdg.WmBase = null,
    egl_display: egl.EGLDisplay,
    egl_config: egl.EGLConfig,
    egl_context: egl.EGLContext,
    should_close: bool = false,

    pub fn init(alloc: std.mem.Allocator) !*Zeichnung {
        const self: *Zeichnung = try alloc.create(Zeichnung);
        self.allocator = alloc;
        self.shm_supported_formats = std.ArrayList(wl.Shm.Format).init(alloc);
        self.display = try wl.Display.connect(null);

        self.registry = try self.display.getRegistry();
        self.registry.setListener(*Zeichnung, registryListener, self);

        // perform round-trip to register compositor, seat, shm & xdg_wm_base
        if (self.display.roundtrip() != .SUCCESS) {
            return error.RoundTripFailed;
        }

        std.debug.assert(self.compositor != null);
        std.debug.assert(self.seat != null);
        std.debug.assert(self.shm != null);
        std.debug.assert(self.xdg_wm_base != null);

        self.egl_display = egl.eglGetPlatformDisplay(egl.EGL_PLATFORM_WAYLAND_KHR, @ptrCast(self.display), null);
        if (self.egl_display == egl.EGL_NO_DISPLAY) {
            return error.EGLInitializationFailed;
        }
        var major: c_int = undefined;
        var minor: c_int = undefined;
        if (egl.eglInitialize(self.egl_display, &major, &minor) != 1) {
            return error.EGLInitializationFailed;
        }
        std.debug.print("EGL version {}.{}\n", .{ major, minor });

        var possible_configs: [10]egl.EGLConfig = undefined;
        var num_configs: c_int = undefined;
        const attribs: []const c_int = &.{
            egl.EGL_SURFACE_TYPE,
            egl.EGL_WINDOW_BIT,
            egl.EGL_BUFFER_SIZE,
            32,
            egl.EGL_COLOR_BUFFER_TYPE,
            egl.EGL_RGB_BUFFER,
            egl.EGL_RED_SIZE,
            8,
            egl.EGL_BLUE_SIZE,
            8,
            egl.EGL_GREEN_SIZE,
            8,
            egl.EGL_ALPHA_SIZE,
            8,
            egl.EGL_RENDERABLE_TYPE,
            egl.EGL_OPENGL_BIT,
            egl.EGL_NONE,
        };
        _ = egl.eglChooseConfig(self.egl_display, @ptrCast(attribs.ptr), &possible_configs, 10, &num_configs);

        self.egl_config = possible_configs[0];

        if (egl.eglBindAPI(egl.EGL_OPENGL_API) == egl.EGL_FALSE) {
            return error.OpenGLApiBindingFailed;
        }
        const attribs2: []const c_int = &.{ egl.EGL_CONTEXT_MAJOR_VERSION, 4, egl.EGL_CONTEXT_MINOR_VERSION, 6, egl.EGL_NONE };
        self.egl_context = egl.eglCreateContext(self.egl_display, self.egl_config, egl.EGL_NO_CONTEXT, @ptrCast(attribs2));
        if (self.egl_context == egl.EGL_NO_CONTEXT) {
            return error.ContextCreationFailed;
        }

        if (self.display.roundtrip() != .SUCCESS) {
            return error.RoundTripFailed;
        }

        if (self.display.roundtrip() != .SUCCESS) {
            return error.RoundTripFailed;
        }

        return self;
    }

    pub fn deinit(self: *Zeichnung) void {
        if (egl.eglTerminate(self.egl_display) != 1) {
            @panic("EGL termination failed!");
        }
        self.shm_supported_formats.deinit();
        self.allocator.destroy(self);
    }

    fn isObject(interface: []const u8, object: anytype) bool {
        return std.mem.eql(u8, interface, std.mem.span(object.getInterface().name));
    }

    fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, self: *Zeichnung) void {
        switch (event) {
            .global => |global| {
                const interface = std.mem.span(global.interface);
                if (isObject(interface, wl.Seat)) {
                    self.seat = registry.bind(global.name, wl.Seat, 3) catch return;
                    self.seat.?.setListener(*Zeichnung, seatListener, self);
                } else if (isObject(interface, wl.Compositor)) {
                    self.compositor = registry.bind(global.name, wl.Compositor, 6) catch return;
                } else if (isObject(interface, wl.Shm)) {
                    self.shm = registry.bind(global.name, wl.Shm, 1) catch return;
                    self.shm.?.setListener(*Zeichnung, shmListener, self);
                } else if (isObject(interface, xdg.WmBase)) {
                    self.xdg_wm_base = registry.bind(global.name, xdg.WmBase, 6) catch return;
                    self.xdg_wm_base.?.setListener(*Zeichnung, xdgWmBaseListener, self);
                } else {
                    std.debug.print("Unhandled interface: {s}\n", .{interface});
                }
            },
            .global_remove => {},
        }
    }

    fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, self: *Zeichnung) void {
        switch (event) {
            .name => {
                std.debug.print("Seat name: {s}\n", .{event.name.name});
            },
            .capabilities => {
                const caps = event.capabilities.capabilities;
                std.debug.print("Seat caps: {any}\n", .{caps});
                if (caps.pointer) {
                    const ptr = seat.getPointer() catch @panic("Pointer was announced but was not able to get it.");
                    std.debug.print("Pointer: {}\n", .{ptr});
                    ptr.setListener(*Zeichnung, pointerListener, self);
                }
            },
        }
    }
    // enter:  struct {serial:u32,surface:?*client.wl.Surface,surface_x:common.Fixed,surface_y:common.Fixed,},
    // leave:  struct {serial:u32,surface:?*client.wl.Surface,},
    // motion: struct {time:u32,surface_x:common.Fixed,surface_y:common.Fixed,},
    // button: struct {serial:u32,time:u32,button:u32,state:ButtonState,},
    // axis:   struct {time:u32,axis:Axis,value:common.Fixed,},
    fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, self: *Zeichnung) void {
        _ = pointer;
        switch (event) {
            .enter => {
                const ev = event.enter;
                std.debug.print("enter: serial {}, surface {*}, surface_x {}, surface_y {}\n", .{ ev.serial, ev.surface, ev.surface_x, ev.surface_y });
            },
            .leave => {
                const ev = event.leave;
                std.debug.print("leave: serial {}, surface {*}\n", .{ ev.serial, ev.surface });
            },
            .motion => {
                const ev = event.motion;
                _ = ev;
                // std.debug.print("motion: time {}, surface_x {}, surface_y {}\n", .{ ev.time, ev.surface_x, ev.surface_y });
            },
            .button => {
                const ev = event.button;
                std.debug.print("button: serial {}, time {}, button: {}, state: {}\n", .{ ev.serial, ev.time, ev.button, ev.state });
                if (ev.button == 272) {
                    self.should_close = true;
                }
            },
            .axis => {
                const ev = event.axis;
                std.debug.print("axis: time {}, axis {}, value {}\n", .{ ev.time, ev.axis, ev.value });
            },
            .frame => {
                std.debug.print("frame end.\n", .{});
            },
            .axis_source => {
                std.debug.print("{}\n", .{event.axis_source});
            },
            .axis_stop => {
                std.debug.print("{}\n", .{event.axis_stop});
            },
            .axis_discrete => {
                std.debug.print("{}\n", .{event.axis_discrete});
            },
            .axis_value120 => {
                std.debug.print("{}\n", .{event.axis_value120});
            },
        }
    }

    fn compositorListener(seat: *wl.Shm, event: wl.Shm.Event, self: *Zeichnung) void {
        _ = seat;
        _ = self;
        std.debug.print("compositorListener: {any}\n", .{event});
    }

    fn shmListener(seat: *wl.Shm, event: wl.Shm.Event, self: *Zeichnung) void {
        _ = seat;
        switch (event) {
            .format => |f| {
                self.shm_supported_formats.append(f.format) catch @panic("Zeichnung OoM!");
            },
        }
    }

    pub fn xdgWmBaseListener(base: *xdg.WmBase, event: xdg.WmBase.Event, self: *Zeichnung) void {
        _ = self;
        switch (event) {
            .ping => |p| {
                base.pong(p.serial);
            },
        }
    }

    pub fn poll(self: *Zeichnung) !bool {
        if (self.display.roundtrip() != .SUCCESS) {
            return error.RoundTripFailed;
        }
        return !self.should_close;
    }

    pub fn createWindow(self: *Zeichnung, title: []const u8, width: usize, height: usize) !*Window {
        return Window.init(self, title, width, height);
    }
};

pub const Window = struct {
    z: *Zeichnung,
    wl_surface: *wl.Surface,
    xdg_surface: *xdg.Surface,
    xdg_toplevel: *xdg.Toplevel,
    egl_surface: egl.EGLSurface,
    wl_egl_window: *egl.wl_egl_window,
    should_close: bool = false,
    w: usize = 0,
    h: usize = 0,

    fn init(z: *Zeichnung, title: []const u8, width: usize, height: usize) !*Window {
        var window = try z.allocator.create(Window);
        window.z = z;
        window.w = width;
        window.h = height;

        window.should_close = false;

        window.wl_surface = try z.compositor.?.createSurface();
        window.xdg_surface = try z.xdg_wm_base.?.getXdgSurface(window.wl_surface);
        window.xdg_surface.setListener(*Window, Window.xdgSurfaceEvent, window);
        window.xdg_toplevel = try window.xdg_surface.getToplevel();
        window.xdg_toplevel.setListener(*Window, Window.xdgToplevelEvent, window);
        window.xdg_toplevel.setMinSize(@intCast(width), @intCast(height));

        _ = z.display.roundtrip();

        window.wl_egl_window = egl.wl_egl_window_create(@ptrCast(window.wl_surface), @intCast(width), @intCast(height)).?;
        try window.createSurface();

        window.setTitle(title);
        try window.makeContextCurrent();

        return window;
    }

    fn createSurface(self: *Window) !void {
        self.wl_surface.commit();
        self.egl_surface = egl.eglCreatePlatformWindowSurface(self.z.egl_display, self.z.egl_config, self.wl_egl_window, null);
        if (self.egl_surface == egl.EGL_NO_SURFACE) {
            return error.EGLSurfaceCreationFailed;
        }
    }

    pub fn deinit(self: *Window) void {
        _ = egl.eglDestroySurface(self.z.egl_display, self.egl_surface);
        self.should_close = true;
        egl.wl_egl_window_destroy(self.wl_egl_window);
        self.xdg_toplevel.destroy();
        self.xdg_surface.destroy();
        self.wl_surface.destroy();
        self.z.allocator.destroy(self);
    }

    fn reconfigure(self: *Window, width: usize, height: usize) void {
        std.debug.print("reconfigure({}, {}).\n", .{ width, height });
        // if (width != 0 and height != 0) {
        self.w = width;
        self.h = height;
        egl.wl_egl_window_resize(@ptrCast(self.wl_egl_window), @intCast(width), @intCast(height), 0, 0);
        // }
        self.wl_surface.damage(0, 0, @intCast(width), @intCast(height));
        self.wl_surface.commit();
    }

    fn xdgSurfaceEvent(surface: *xdg.Surface, event: xdg.Surface.Event, self: *Window) void {
        switch (event) {
            .configure => |conf| {
                self.reconfigure(self.w, self.h);
                surface.ackConfigure(conf.serial);
            },
        }
    }

    fn xdgToplevelEvent(surface: *xdg.Toplevel, event: xdg.Toplevel.Event, self: *Window) void {
        _ = surface;
        switch (event) {
            .configure => |conf| {
                std.debug.print("Window: {*}; width: {}, height: {}\n", .{ self, conf.width, conf.height });
                self.reconfigure(@intCast(conf.width), @intCast(conf.height));
            },
            .close => {
                self.should_close = true;
            },
            .configure_bounds => {
                std.debug.print("Unhandled configure_bounds: {any}\n", .{event.configure_bounds});
            },
            .wm_capabilities => {
                std.debug.print("Unhandled wm_capabilities: {any}\n", .{event.wm_capabilities});
            },
        }
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        var buf: [1024]u8 = undefined;
        @memcpy(buf[0..title.len], title);
        buf[title.len] = 0;
        self.xdg_toplevel.setTitle(@ptrCast(buf[0..title.len]));
    }

    pub fn makeContextCurrent(self: *Window) !void {
        if (egl.eglMakeCurrent(self.z.egl_display, self.egl_surface, self.egl_surface, self.z.egl_context) != egl.EGL_TRUE) {
            const err = egl.eglGetError();
            return switch (err) {
                egl.EGL_BAD_MATCH => error.BadMatch,
                egl.EGL_BAD_ACCESS => error.BadAccess,
                egl.EGL_BAD_NATIVE_WINDOW => error.BadNativeWindow,
                egl.EGL_BAD_CURRENT_SURFACE => error.BadCurrentSurface,
                egl.EGL_BAD_ALLOC => error.LBadAlloc,
                egl.EGL_CONTEXT_LOST => error.ContextLost,
                else => error.UnknownEGLError,
            };
        }
    }

    pub fn swapBuffers(self: *Window) !void {
        // _ = libdecor.libdecor_dispatch(@ptrCast(self.z.decor.ctx), 0);
        if (egl.eglSwapBuffers(self.z.egl_display, self.egl_surface) != egl.EGL_TRUE) {
            const err = egl.eglGetError();
            return switch (err) {
                egl.EGL_BAD_DISPLAY => error.BadDisplay,
                egl.EGL_NOT_INITIALIZED => error.NotInitialized,
                egl.EGL_BAD_SURFACE => error.BadSurface,
                egl.EGL_CONTEXT_LOST => error.ContextLost,
                else => error.UnknownEGLError,
            };
        }
    }
};

pub const Timer = struct {
    timer: std.time.Timer,
    pub fn init() !Timer {
        return Timer{
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn reset(self: *Timer) void {
        self.timer.reset();
    }

    pub fn nanos(self: *Timer, comptime T: type) T {
        switch (@typeInfo(T)) {
            .int => return @intCast(self.timer.read()),
            .float => return @floatFromInt(self.timer.read()),
            else => @compileError("Unsupported time output: " ++ @typeName(T)),
        }
    }

    pub fn secs(self: *Timer, comptime T: type) T {
        switch (@typeInfo(T)) {
            .int => return self.nanos(T) / @as(T, @intCast(std.time.ns_per_s)),
            .float => return self.nanos(T) / @as(T, @floatFromInt(std.time.ns_per_s)),
            else => @compileError("Unsupported time output: " ++ @typeName(T)),
        }
    }

    pub fn millis(self: *Timer, comptime T: type) T {
        switch (@typeInfo(T)) {
            .int => return self.nanos(T) / @as(T, @intCast(std.time.ns_per_ms)),
            .float => return self.nanos(T) / @as(T, @floatFromInt(std.time.ns_per_ms)),
            else => @compileError("Unsupported time output: " ++ @typeName(T)),
        }
    }

    pub fn micros(self: *Timer, comptime T: type) T {
        switch (@typeInfo(T)) {
            .int => return self.nanos(T) / @as(T, @intCast(std.time.ns_per_us)),
            .float => return self.nanos(T) / @as(T, @floatFromInt(std.time.ns_per_us)),
            else => @compileError("Unsupported time output: " ++ @typeName(T)),
        }
    }
};
