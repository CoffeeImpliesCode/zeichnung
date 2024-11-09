const std = @import("std");
const z = @import("root.zig");
const Allocator = std.mem.Allocator;

const gl = @cImport({
    @cInclude("KHR/khrplatform.h");
    @cInclude("glad/gl.h");
});

pub fn loadShader(alloc: Allocator, vertex_path: []const u8, fragment_path: []const u8) !gl.GLuint {
    const vf = try std.fs.cwd().openFile(vertex_path, .{});
    defer vf.close();
    const vbytes = try vf.readToEndAllocOptions(alloc, 10000000, null, 4, 0);
    defer alloc.free(vbytes);
    const ff = try std.fs.cwd().openFile(fragment_path, .{});
    defer ff.close();
    const fbytes = try vf.readToEndAllocOptions(alloc, 10000000, null, 4, 0);
    defer alloc.free(fbytes);

    const vs: gl.GLuint = gl.glCreateShader(gl.GL_VERTEX_SHADER);
    gl.glShaderSource(vs, 1, @ptrCast(&vbytes.ptr), @ptrCast(&.{vbytes.len}));
    gl.glCompileShader(vs);

    var compile_status: c_int = gl.GL_FALSE;
    gl.glGetShaderiv(vs, gl.GL_COMPILE_STATUS, &compile_status);
    if (compile_status != gl.GL_TRUE) {
        var errbuf: [512]u8 = undefined;
        @memset(errbuf[0..512], 0);
        gl.glGetShaderInfoLog(vs, 512, null, @ptrCast(&errbuf));
        std.debug.print("{s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&errbuf)))});
        return error.VertexCompilationFailed;
    }

    const fs: gl.GLuint = gl.glCreateShader(gl.GL_FRAGMENT_SHADER);
    gl.glShaderSource(fs, 1, @ptrCast(&fbytes.ptr), @ptrCast(&.{fbytes.len}));
    gl.glCompileShader(fs);

    compile_status = gl.GL_FALSE;
    gl.glGetShaderiv(fs, gl.GL_COMPILE_STATUS, &compile_status);
    if (compile_status != gl.GL_TRUE) {
        var errbuf: [512]u8 = undefined;
        @memset(errbuf[0..512], 0);
        gl.glGetShaderInfoLog(fs, 512, null, @ptrCast(&errbuf));
        std.debug.print("{s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(&errbuf)))});
        return error.FragmentCompilationFailed;
    }

    const p = gl.glCreateProgram();
    gl.glAttachShader(p, vs);
    gl.glAttachShader(p, fs);
    gl.glLinkProgram(p);
    gl.glValidateProgram(p);

    var link_status: c_uint = gl.GL_FALSE;
    gl.glGetProgramiv(p, gl.GL_LINK_STATUS, @ptrCast(&link_status));
    if (link_status != gl.GL_TRUE) {
        gl.glGetProgramInfoLog(p, @intCast(vbytes.len), null, @ptrCast(vbytes.ptr));
        std.debug.print("{s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(vbytes.ptr)))});
        return error.ProgramLinkingFailed;
    }

    gl.glDetachShader(p, vs);
    gl.glDetachShader(p, fs);
    // gl.glDeleteShader(vs);
    // gl.glDeleteShader(fs);

    return p;
}

var GL: ?*std.DynLib = null;

pub fn loadGLFunc(f: [*:0]const u8) callconv(.C) ?*anyopaque {
    return GL.?.lookup(*anyopaque, std.mem.span(f));
}

pub fn glDebugProc(source: gl.GLenum, @"type": gl.GLenum, id: gl.GLuint, severity: gl.GLenum, length: gl.GLsizei, message: [*c]gl.GLchar, userParam: *anyopaque) callconv(.C) void {
    _ = source;
    _ = @"type";
    _ = id;
    _ = severity;
    _ = length;
    _ = userParam;
    std.debug.print("GL debug: {s}\n", .{std.mem.span(message)});
}

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const alloc = GPA.allocator();

    var ctx = try z.Zeichnung.init(alloc);
    defer ctx.deinit();

    _ = try ctx.poll();

    const w = try ctx.createWindow("Hello, world!", 800, 600);
    defer w.deinit();

    GL = @constCast(&(try std.DynLib.open("libGL.so")));

    try w.makeContextCurrent();
    const gl_version = gl.gladLoadGL(@ptrCast(&loadGLFunc));
    std.debug.print("GL {}.{}\n", .{ gl.GLAD_VERSION_MAJOR(gl_version), gl.GLAD_VERSION_MINOR(gl_version) });
    gl.glEnable(gl.GL_DEBUG_OUTPUT);
    gl.glDebugMessageCallback(@ptrCast(&glDebugProc), null);

    // desperation...
    // gl.glDisable(gl.GL_DEPTH_TEST);
    // gl.glDisable(gl.GL_SCISSOR_TEST);
    // gl.glDisable(gl.GL_CULL_FACE);
    // gl.glDisable(gl.GL_BLEND);
    // gl.glFrontFace(gl.GL_CCW);
    // gl.glPolygonMode(gl.GL_FRONT_AND_BACK, gl.GL_FILL);

    w.setTitle("Hello, world!");

    const prog = try loadShader(alloc, "shader/quad.vert", "shader/quad.frag");
    const data: []const f32 = &.{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 };

    var vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, @ptrCast(&vao));
    std.debug.assert(vao != 0);
    gl.glBindVertexArray(vao);
    var vbo: gl.GLuint = 0;
    gl.glGenBuffers(1, @ptrCast(&vbo));
    std.debug.assert(vbo != 0);

    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(std.mem.sliceAsBytes(data).len), @ptrCast(data.ptr), gl.GL_STATIC_DRAW);
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 2 * @sizeOf(f32), null);

    var timer = try z.Timer.init();

    gl.glClearColor(1.0, 0.0, 0.0, 1.0);
    while (!w.should_close and (try ctx.poll())) {
        const t = timer.secs(f32);
        // _ = t;
        gl.glViewport(0, 0, @intCast(w.w), @intCast(w.h));
        gl.glClearColor(1.0, 0.0, 0.0, 0.5 - 0.5 * @cos(2.0 * t));
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        gl.glUseProgram(prog);
        gl.glBindVertexArray(vao);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);
        // gl.glFlush();
        // gl.glFinish();
        try w.swapBuffers();
        // w.wl_surface.damage(0, 0, w.w, w.h);
        // w.wl_surface.commit();
        // _ = w.z.display.flush();
        // _ = w.z.display.dispatch();
    }
}
