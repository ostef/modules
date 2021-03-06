#module_parameters (MAX_VERTICES := 10000);

// @Todo (stefan): Layers

#scope_module

#import "Runtime";
mem    :: #import "Memory";
log    :: #import "Log";
math   :: #import "Math";
using linalg :: #import "Linalg";
window :: #import "Window";
gl     :: #import "GL";
render :: #import "Render_Core";
font   :: #import "Font";
array  :: #import "Containers/Array";

Recti :: math.Recti;
Rectf :: math.Rectf;
RGBA  :: math.RGBA;

#scope_export

#load "draw.jai";
#load "command_renderer.jai";

Vertex :: struct
{
	position   : Vec2f;
	tex_coords : Vec2f;
	color      : RGBA;

	LAYOUT :: render.Vertex_Buffer.Elem.[
		render.Vertex_Buffer.VEC2F,
		render.Vertex_Buffer.VEC2F,
		render.Vertex_Buffer.RGBA
	];
}

Draw_Context :: struct
{
	win    : *window.Window;
	gl_ctx : *gl.GL_Context;

	vertices : [MAX_VERTICES]Vertex;
	vertex_count : s64;
	clip_rect : Recti;
	clipping_enabled : bool;
	viewport : Recti;

	texture        : *render.Texture;
	framebuffer    : *render.Framebuffer;
	shader         : *render.Shader;
	vertex_buffer  : render.Vertex_Buffer;
	default_shader : render.Shader;
}

#add_context imdraw_context : *Draw_Context;	// Currently active ImDraw context

Rectangle_Corners :: enum_flags
{
	NONE         :: 0x00;
	TOP_LEFT     :: 0x01;
	TOP_RIGHT    :: 0x02;
	BOTTOM_RIGHT :: 0x04;
	BOTTOM_LEFT  :: 0x08;
	ALL :: TOP_LEFT | TOP_RIGHT | BOTTOM_RIGHT | BOTTOM_LEFT;
}

check_init :: () #expand
{
	`imdraw := context.imdraw_context;
	assert (imdraw != null, "No drawing context.");
}

create_context :: inline (win : *window.Window, gl_ctx : *gl.GL_Context) -> *Draw_Context #must
{
	if !win || !gl_ctx
		return null;
	imdraw := mem.alloc (Draw_Context, mem.HEAP_ALLOC);
	if !imdraw
		return null;
	imdraw.win = win;
	imdraw.gl_ctx = gl_ctx;
	shader_ok, info_log := render.init_shader (*imdraw.default_shader, GL_VERTEX_SHADER, GL_FRAGMENT_SHADER);
	if !shader_ok
	{
		log.error ("Could not load ImDraw default shader:\n%", info_log);
		destroy_context (imdraw);
		return null;
	}
	render.init_vertex_buffer (*imdraw.vertex_buffer, Vertex.LAYOUT);
	render.allocate_vertex_buffer_data (*imdraw.vertex_buffer, MAX_VERTICES * size_of (Vertex), .DYNAMIC_DRAW);

	return imdraw;
}

destroy_context :: inline (imdraw : *Draw_Context)
{
	assert (context.imdraw_context != imdraw, "Cannot destroy ImDraw context because it is in use; end was not called.");
	render.destroy_vertex_buffer (*imdraw.vertex_buffer);
	render.destroy_shader (*imdraw.default_shader);
	mem.free (imdraw, mem.HEAP_ALLOC);
}

begin :: inline (imdraw : *Draw_Context)
{
	assert (context.imdraw_context != imdraw, "Called begin before calling end on the same context.");
	assert (context.imdraw_context == null, "Called begin but another context is in use.");
	assert (gl.get_current_context () == imdraw.gl_ctx, "Current GL context does not match ImDraw GL context.");
	context.imdraw_context = imdraw;
}

end :: inline ()
{
	flush ();
	context.imdraw_context = null;
}

flush :: inline ()
{
	check_init ();
	if imdraw.vertex_count == 0
		return;
	shader := ifx imdraw.shader then imdraw.shader else *imdraw.default_shader;
	prev_vertex_buffer := render.use_vertex_buffer (*imdraw.vertex_buffer);
	defer render.use_vertex_buffer (*prev_vertex_buffer);
	prev_shader := render.use_shader (shader);
	defer render.use_shader (*prev_shader);
	prev_texture := render.use_texture (imdraw.texture);
	defer render.use_texture (*prev_texture);
	prev_framebuffer := render.use_framebuffer_for_drawing (imdraw.framebuffer);
	defer render.use_framebuffer_for_drawing (*prev_framebuffer);

	viewport := imdraw.viewport;
	if !imdraw.framebuffer
	{
		viewport_w, viewport_h := window.get_viewport_size (imdraw.win);
		viewport.x = 0;
		viewport.y = 0;
		viewport.w = viewport_w;
		viewport.h = viewport_h;
	}
	view_projection := mat4f_orthographic_projection (
		cast (f32) viewport.x,
		cast (f32) (viewport.x + viewport.w),
		cast (f32) (viewport.y + viewport.h),
		cast (f32) viewport.y,
		0,
		1
	);
	gl.Viewport (viewport.x, viewport.y, xx viewport.w, xx viewport.h);
	render.set_shader_parameter (shader, "u_View_Projection_Matrix", view_projection);
	render.set_shader_parameter (shader, "u_Use_Texture", imdraw.texture != null);

	if imdraw.clipping_enabled
	{
		clip_rect := imdraw.clip_rect;
		clip_rect.y = viewport.h - (clip_rect.y + clip_rect.h);
		gl.Enable (gl.SCISSOR_TEST);
		gl.Scissor (xx clip_rect.x, xx clip_rect.y, xx clip_rect.w, xx clip_rect.h);
	}
	defer gl.Disable (gl.SCISSOR_TEST);
	gl.Disable (gl.DEPTH_TEST);
	gl.Enable (gl.BLEND);
	gl.BlendFunc (gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

	render.set_vertex_buffer_data (*imdraw.vertex_buffer, imdraw.vertices.data, imdraw.vertex_count * size_of (Vertex));
	gl.DrawArrays (gl.TRIANGLES, 0, xx imdraw.vertex_count);
	imdraw.vertex_count = 0;
}

reserve :: inline (count : s64) -> *Vertex #must
#deprecated "Use push_vertices instead."
{
	return push_vertices (count);
}

push_vertices :: inline (count : s64) -> *Vertex #must { check_init (); return push_vertices (imdraw, count); }
push_vertices :: inline (ctx : *Draw_Context, count : s64) -> *Vertex #must
{
	assert (count <= MAX_VERTICES, "Reserving too many vertices (requested %, maximum is %).", count, MAX_VERTICES);
	if ctx.vertex_count + count > MAX_VERTICES
		flush ();
	result := *ctx.vertices[ctx.vertex_count];
	ctx.vertex_count += count;

	return result;
}

get_clip_rect :: inline () -> Recti #must { check_init (); return get_clip_rect (imdraw); }
get_clip_rect :: inline (ctx : *Draw_Context) -> Recti #must
{
	return ctx.clip_rect;
}

set_clip_rect :: inline (clip_rect : Recti) -> previous : Recti { check_init (); return set_clip_rect (imdraw, clip_rect); }
set_clip_rect :: inline (ctx : *Draw_Context, clip_rect : Recti) -> previous : Recti
{;
	previous := ctx.clip_rect;
	// We can't use operator == for rects because it is in math
	if !mem.equals (previous, clip_rect) || !ctx.clipping_enabled then flush ();
	ctx.clipping_enabled = true;
	ctx.clip_rect = clip_rect;
	using ctx.clip_rect;
	if w < 0 then w = 0;
	if h < 0 then h = 0;

	return previous;
}

push_clip_rect :: inline (clip_rect : Recti) -> previous : Recti { check_init (); return push_clip_rect (imdraw, clip_rect); }
push_clip_rect :: inline (renderer : *$T, clip_rect : Recti) -> previous : Recti
{
	check_init ();
	if get_clipping (renderer)
		return set_clip_rect (renderer, math.clip (clip_rect, get_clip_rect (renderer)));
	return set_clip_rect (renderer, clip_rect);
}

scope_clip_rect :: (clip_rect : Recti) #expand
{
	previous_clip := get_clipping ();
	`defer set_clipping (previous_clip);
	previous_rect := push_clip_rect (clip_rect);
	`defer set_clip_rect (previous_rect);
}

scope_clip_rect :: (renderer : *$T, clip_rect : Recti) #expand
{
	previous_clip := get_clipping (renderer);
	`defer set_clipping (renderer, previous_clip);
	previous_rect := push_clip_rect (renderer, clip_rect);
	`defer set_clip_rect (renderer, previous_rect);
}

get_clipping :: inline () -> bool #must { check_init (); return get_clipping (imdraw); }
get_clipping :: inline (ctx : *Draw_Context) -> bool #must
{
	return ctx.clipping_enabled;
}

set_clipping :: inline (enable : bool) -> previous : bool { check_init (); return set_clipping (imdraw, enable); }
set_clipping :: inline (ctx : *Draw_Context, enable : bool) -> previous : bool
{
	previous := ctx.clipping_enabled;
	if previous != enable then flush ();
	ctx.clipping_enabled = enable;
	return previous;
}

get_texture :: inline () -> *render.Texture #must { check_init (); return get_texture (imdraw); }
get_texture :: inline (ctx : *Draw_Context) -> *render.Texture #must
{
	return ctx.texture;
}

set_texture :: inline (texture : *render.Texture) -> previous : *render.Texture { check_init (); return set_texture (imdraw, texture); }
set_texture :: inline (ctx : *Draw_Context, texture : *render.Texture) -> previous : *render.Texture
{
	previous := ctx.texture;
	if previous != texture then flush ();
	ctx.texture = texture;
	return previous;
}

get_shader :: inline () -> *render.Shader #must { check_init (); return get_shader (imdraw); }
get_shader :: inline (ctx : *Draw_Context) -> *render.Shader #must
{
	return ctx.shader;
}

set_shader :: inline (shader : *render.Shader) -> *render.Shader { check_init (); return set_shader (imdraw, shader); }
set_shader :: inline (ctx : *Draw_Context, shader : *render.Shader) -> *render.Shader
{
	previous := ctx.shader;
	if previous != shader then flush ();
	ctx.shader = shader;
	return previous;
}

get_viewport :: inline () -> Recti #must
{
	check_init ();
	return imdraw.viewport;
}

set_viewport :: inline (viewport : Recti) -> Recti
{
	check_init ();
	previous := imdraw.viewport;
	if !mem.equals (previous, viewport) then flush ();
	imdraw.viewport = viewport;
	return previous;
}

get_framebuffer :: inline () -> *render.Framebuffer #must
{
	check_init ();
	return imdraw.framebuffer;
}

set_framebuffer :: inline (framebuffer : *render.Framebuffer) -> *render.Framebuffer
{
	check_init ();
	previous := imdraw.framebuffer;
	if previous != framebuffer then flush ();
	imdraw.framebuffer = framebuffer;
	return previous;
}

#scope_file

GL_VERTEX_SHADER :: #string GLSL
#version 330 core

layout (location = 0) in vec2 a_Position;
layout (location = 1) in vec2 a_Tex_Coords;
layout (location = 2) in vec4 a_Color;

out vec2 Tex_Coords;
out vec4 Color;

uniform mat4 u_View_Projection_Matrix;

void main ()
{
	gl_Position = u_View_Projection_Matrix * vec4 (a_Position, 0, 1);
	Tex_Coords = a_Tex_Coords;
	Color      = a_Color;
}
GLSL

GL_FRAGMENT_SHADER :: #string GLSL
#version 330 core

in vec2 Tex_Coords;
in vec4 Color;

out vec4 Frag_Color;

uniform sampler2D u_Texture;
uniform bool u_Use_Texture;

void main ()
{
	vec4 sampled = vec4 (1, 1, 1, 1);
	if (u_Use_Texture)
		sampled = texture (u_Texture, Tex_Coords);
	Frag_Color = sampled * Color;
}
GLSL
