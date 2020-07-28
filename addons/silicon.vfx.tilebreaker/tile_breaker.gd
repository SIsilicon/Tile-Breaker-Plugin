tool
extends Material
class_name TileBreaker

const SAMPLER_CODE = {
	"global": """
		vec2 noTileRotate(in vec2 point, in float angle) {
			float c = cos(angle);
			float s = sin(angle);
			return vec2(point.x * c - point.y * s, point.x * s + point.y * c);
		}

		vec4 noTileHash4( vec2 p ) {
			return fract(sin(vec4(
				1.0+dot(p,vec2(37.0,17.0)), 
				2.0+dot(p,vec2(11.0,47.0)),
				3.0+dot(p,vec2(41.0,29.0)),
				4.0+dot(p,vec2(23.0,31.0))
			))*103.0);
		}
	""",
	"triplanar": """
		vec4 triplanarTextureNoTile(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos, float p_rotation, float p_blending, bool p_vector_map) {
			vec4 samp = vec4(0.0);
			samp += textureNoTile(p_sampler, p_triplanar_pos.xy, p_rotation, p_blending, p_vector_map) * p_weights.z;
			samp += textureNoTile(p_sampler, p_triplanar_pos.xz, p_rotation, p_blending, p_vector_map) * p_weights.y;
			samp += textureNoTile(p_sampler, p_triplanar_pos.zy * vec2(-1.0,1.0), p_rotation, p_blending, p_vector_map) * p_weights.x;
			return samp;
		}
	""",
	"gles3": {
		"low": """
			uniform sampler2D variation;

			vec4 textureNoTile(sampler2D p_sampler, in vec2 p_uv, in float p_rotation, in float p_blending, in bool p_vector_map) {
				// sample variation pattern    
				float k = texture(variation, 0.005*p_uv).x; // cheap (cache friendly) lookup    

				// compute index    
				float index = k*8.0;
				float i = floor(index);
				float f = fract(index);

				// offsets for the different virtual patterns    
				vec3 offa = sin(vec3(3.0,7.0,9.0)*(i+0.0)); // can replace with any other hash    
				vec3 offb = sin(vec3(3.0,7.0,9.0)*(i+1.0)); // can replace with any other hash    

				// compute derivatives for mip-mapping    
				vec2 dx = dFdx(p_uv), dy = dFdy(p_uv);

				// sample the two closest virtual patterns    
				vec4 cola = textureGrad(p_sampler, noTileRotate(p_uv + offa.xy, p_rotation * offa.z), dx, dy);
				vec4 colb = textureGrad(p_sampler, noTileRotate(p_uv + offb.xy, p_rotation * offb.z), dx, dy);
				if(p_vector_map) {
					cola.rg = 0.5 * noTileRotate(2.0 * cola.rg - 1.0, p_rotation * offa.z) + 0.5;
					colb.rg = 0.5 * noTileRotate(2.0 * colb.rg - 1.0, p_rotation * offb.z) + 0.5;
				}

				// interpolate between the two virtual patterns    
				return mix(cola, colb, smoothstep(0.5-p_blending*0.5, 0.5+p_blending*0.5, f-0.1*dot(cola-colb, vec4(1.0))));
			}
		""",
		"medium": """
			vec4 textureNoTile(sampler2D p_sampler, in vec2 p_uv, in float p_rotation, in float p_blending, in bool p_vector_map) {
				vec2 iuv = floor(p_uv);
				vec2 fuv = fract(p_uv);

				// generate per-tile transform
				vec4 ofa = noTileHash4(iuv + vec2(0.0,0.0));
				vec4 ofb = noTileHash4(iuv + vec2(1.0,0.0));
				vec4 ofc = noTileHash4(iuv + vec2(0.0,1.0));
				vec4 ofd = noTileHash4(iuv + vec2(1.0,1.0));

				vec2 ddx = dFdx(p_uv);
				vec2 ddy = dFdy(p_uv);

				// p_uv's, and derivarives (for correct mipmapping)
				vec4 rot = p_rotation * (vec4(ofa.z, ofb.z, ofc.z, ofd.z) * 2.0 - 1.0);
				vec2 uva = noTileRotate(p_uv + ofa.xy, rot.x); vec2 ddxa = noTileRotate(ddx, rot.x); vec2 ddya = noTileRotate(ddy, rot.x);
				vec2 uvb = noTileRotate(p_uv + ofb.xy, rot.y); vec2 ddxb = noTileRotate(ddx, rot.y); vec2 ddyb = noTileRotate(ddy, rot.y);
				vec2 uvc = noTileRotate(p_uv + ofc.xy, rot.z); vec2 ddxc = noTileRotate(ddx, rot.z); vec2 ddyc = noTileRotate(ddy, rot.z);
				vec2 uvd = noTileRotate(p_uv + ofd.xy, rot.w); vec2 ddxd = noTileRotate(ddx, rot.w); vec2 ddyd = noTileRotate(ddy, rot.w);

				// fetch and p_blending
				vec2 b = smoothstep(0.5-p_blending*0.5, 0.5+p_blending*0.5, fuv);

				vec4 cola = textureGrad(p_sampler, uva, ddxa, ddya);
				vec4 colb = textureGrad(p_sampler, uvb, ddxb, ddyb);
				vec4 colc = textureGrad(p_sampler, uvc, ddxc, ddyc);
				vec4 cold = textureGrad(p_sampler, uvd, ddxd, ddyd);
				if(p_vector_map) {
					cola.rg = 0.5 * noTileRotate(2.0 * cola.rg - 1.0, rot.x) + 0.5;
					colb.rg = 0.5 * noTileRotate(2.0 * colb.rg - 1.0, rot.y) + 0.5;
					colc.rg = 0.5 * noTileRotate(2.0 * colc.rg - 1.0, rot.z) + 0.5;
					cold.rg = 0.5 * noTileRotate(2.0 * cold.rg - 1.0, rot.w) + 0.5;
				}

				return mix( mix(cola, colb, b.x),
							mix(colc, cold, b.x), b.y);
			}
		""",
		"high": """
			vec4 textureNoTile(sampler2D p_sampler, in vec2 p_uv, in float p_rotation, in float p_blending, in bool p_vector_map) {
				vec2 p = floor(p_uv);
				vec2 f = fract(p_uv);

				// derivatives (for correct mipmapping)
				vec2 ddx = dFdx(p_uv);
				vec2 ddy = dFdy(p_uv);

				vec4 va = vec4(0.0);
				float w1 = 0.0;
				float w2 = 0.0;
				for( int j=-1; j<=1; j++ )
				for( int i=-1; i<=1; i++ ) {
					vec2 g = vec2(float(i), float(j));
					vec4 o = noTileHash4(p + g);
					vec2 vp = o.xy + f;
					vec2 r = g - f + o.xy;
					float d = dot(r,r);
					float w = exp(-mix(80.0, 5.0, pow(p_blending, 0.5)) * d);
					float rot = p_rotation * (2.0 * o.y - 1.0);
					vec4 c = textureGrad(p_sampler, noTileRotate(p_uv + o.zw, rot),
							noTileRotate(ddx, rot), noTileRotate(ddy, rot));
					if(p_vector_map) {
						c.rg = 0.5 * noTileRotate(2.0 * c.rg - 1.0, rot) + 0.5;
					}

					va += w*c;
					w1 += w;
					w2 += w*w;
				}
				return va/w1;
			}
		"""
	},
	"gles2": {
		"low": """
			uniform sampler2D variation;

			vec4 textureNoTile(sampler2D p_sampler, in vec2 p_uv, in float p_rotation, in float p_blending, in bool p_vector_map) {
				// sample variation pattern    
				float k = texture(variation, 0.005*p_uv).x; // cheap (cache friendly) lookup    

				// compute index    
				float index = k*8.0;
				float i = floor(index);
				float f = fract(index);

				// offsets for the different virtual patterns    
				vec3 offa = sin(vec3(3.0,7.0,9.0)*(i+0.0)); // can replace with any other hash    
				vec3 offb = sin(vec3(3.0,7.0,9.0)*(i+1.0)); // can replace with any other hash    

				// sample the two closest virtual patterns    
				vec4 cola = texture(p_sampler, noTileRotate(p_uv + offa.xy, p_rotation * offa.z));
				vec4 colb = texture(p_sampler, noTileRotate(p_uv + offb.xy, p_rotation * offb.z));
				if(p_vector_map) {
					cola.rg = 0.5 * noTileRotate(2.0 * cola.rg - 1.0, p_rotation * offa.z) + 0.5;
					colb.rg = 0.5 * noTileRotate(2.0 * colb.rg - 1.0, p_rotation * offb.z) + 0.5;
				}

				// interpolate between the two virtual patterns    
				return mix(cola, colb, smoothstep(0.5-p_blending*0.5, 0.5+p_blending*0.5, f-0.1*dot(cola-colb, vec4(1.0))));
			}
		""",
		"medium": """
			vec4 textureNoTile(sampler2D p_sampler, in vec2 p_uv, in float p_rotation, in float p_blending) {
				vec2 iuv = floor(p_uv);
				vec2 fuv = fract(p_uv);

				// generate per-tile transform
				vec4 ofa = noTileHash4(iuv + vec2(0.0,0.0));
				vec4 ofb = noTileHash4(iuv + vec2(1.0,0.0));
				vec4 ofc = noTileHash4(iuv + vec2(0.0,1.0));
				vec4 ofd = noTileHash4(iuv + vec2(1.0,1.0));

				// p_uv's, and derivarives (for correct mipmapping)
				vec4 rot = p_rotation * (vec4(ofa.z, ofb.z, ofc.z, ofd.z) * 2.0 - 1.0);
				vec2 uva = noTileRotate(p_uv + ofa.xy, rot.x);
				vec2 uvb = noTileRotate(p_uv + ofb.xy, rot.y);
				vec2 uvc = noTileRotate(p_uv + ofc.xy, rot.z);
				vec2 uvd = noTileRotate(p_uv + ofd.xy, rot.w);

				// fetch and p_blending
				vec2 b = smoothstep(0.5-p_blending*0.5, 0.5+p_blending*0.5, fuv);

				vec4 cola = texture(p_sampler, uva);
				vec4 colb = texture(p_sampler, uvb);
				vec4 colc = texture(p_sampler, uvc);
				vec4 cold = texture(p_sampler, uvd);
				if(p_vector_map) {
					cola.rg = 0.5 * noTileRotate(2.0 * cola.rg - 1.0, rot.x) + 0.5;
					colb.rg = 0.5 * noTileRotate(2.0 * colb.rg - 1.0, rot.y) + 0.5;
					colc.rg = 0.5 * noTileRotate(2.0 * colc.rg - 1.0, rot.z) + 0.5;
					cold.rg = 0.5 * noTileRotate(2.0 * cold.rg - 1.0, rot.w) + 0.5;
				}

				return mix( mix(cola, colb, b.x),
							mix(colc, cold, b.x), b.y);
			}
		""",
		"high": """
			vec4 textureNoTile(sampler2D p_sampler, in vec2 p_uv, in float p_rotation, in float p_blending) {
				vec2 p = floor(p_uv);
				vec2 f = fract(p_uv);

				vec4 va = vec4(0.0);
				float w1 = 0.0;
				float w2 = 0.0;
				for( int j=-1; j<=1; j++ )
				for( int i=-1; i<=1; i++ ) {
					vec2 g = vec2(float(i), float(j));
					vec4 o = noTileHash4(p + g);
					vec2 vp = o.xy + f;
					vec2 r = g - f + o.xy;
					float d = dot(r,r);
					float w = exp(-mix(80.0, 5.0, pow(p_blending, 0.5)) * d);
					float rot = p_rotation * (2.0 * o.y - 1.0);
					vec4 c = texture(p_sampler, noTileRotate(p_uv + o.zw, rot));
					if(p_vector_map) {
						c.rg = 0.5 * noTileRotate(2.0 * c.rg - 1.0, rot) + 0.5;
					}

					va += w*c;
					w1 += w;
					w2 += w*w;
				}
				return va/w1;
			}
		"""
	}
}


static func get_sampler_code() -> String:
	var quality: int = ProjectSettings.get("rendering/quality/tile_breaker/quality")
	var global: String = SAMPLER_CODE.global.replace("\n\t\t", "\n")

	var gles := "gles3" if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3 else "gles2"
	var sampler: String
	match quality:
		0: sampler = SAMPLER_CODE[gles].low
		1: sampler = SAMPLER_CODE[gles].medium
		2: sampler = SAMPLER_CODE[gles].high
	sampler = sampler.replace("\n\t\t\t", "\n")

	return global + sampler


static func find_texture_function(code: String, function := "texture", start_at := 0) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("[^\\w]"+function+"\\s*(\\()\\s*(\\w*)")
	var regexmatch := regex.search(code, start_at)
	if regexmatch and regexmatch.get_start() != -1:
		return {
			"index": regexmatch.get_start() + 1,
			"bracket": regexmatch.get_start(1),
			"texture": regexmatch.get_string(2)
		}
	return {}


static func find_closing_bracket(string : String, open_bracket_idx : int) -> int:
	var bracket_count := 1
	var open_bracket := string.substr(open_bracket_idx, 1)
	var close_bracket := "}" if open_bracket == "{" else ")" if open_bracket == "(" else "]"
	var index := open_bracket_idx
	
	while index < string.length():
		var open_index = string.find(open_bracket, index+1)
		var close_index = string.find(close_bracket, index+1)
		
		if close_index != -1 and (open_index == -1 or close_index < open_index):
			index = close_index
			bracket_count -= 1
		elif open_index != -1 and (close_index == -1 or open_index < close_index):
			index = open_index
			bracket_count += 1
		else:
			return -1
		
		if bracket_count <= 0:
			return index
	
	return -1
