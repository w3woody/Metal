//
//  MXFairyIllumination.metal
//  Metal
//
//  Created by William Woody on 1/4/19.
//  Copyright © 2019 Glenview Software. All rights reserved.
//

#include <metal_stdlib>
#include "MXShaderTypes.h"

using namespace metal;

/****************************************************************************/
/*																			*/
/*	Geometry Structures														*/
/*																			*/
/****************************************************************************/

/*	VertexIn
 *
 *		The vertex format for geometry read in from our buffer. Note that
 *	this **MUST MATCH** the declaration in MXGeometry.h for MXFairyVertex.
 */

struct VertexIn {
    float2 position		[[attribute(MXAttributeIndexPosition)]];
};

/*	FairyLightIn
 *
 *		Location and positions of the fairy lights. (This contains additional
 *	information not used in this renderer.) Because we can this through an
 *	array of these objects we don't need to declare their attributes.
 */

struct FairyLightIn {
	float3 position;
	float3 color;
	float size;

	float2 angle;
	float speed;
	float radius;
};

struct VertexOut
{
	float4 position [[position]];
	float3 lightPos;
	float2 xy;
	float2 uv;
	float3 color;
};


/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	vertex_illumination
 *
 *		This is a stripped down version of the vertex_main function that is
 *	used for building our shadow map. We don't care about anything but the
 *	depth, so this skips initializing a bunch of stuff.
 */

vertex VertexOut vertex_illumination(VertexIn v [[stage_in]],
							  constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]],
							  constant FairyLightIn *positions [[buffer(MXVertexIndexLocations)]],
							  uint iid [[instance_id]])
{
	VertexOut out;

	// Transform location and offset
	float4 worldPos = u.model * float4(positions[iid].position,1.0);
	float4 screenPos = u.view * worldPos;
	// Offset the X/Y location. Note this is 5 times bigger than with
	// the fairy light shaders.
	screenPos.xy += v.position * 0.15 * positions[iid].size;
	out.position = screenPos;

	float2 screenXY = screenPos.xy / screenPos.w;

	// Pass through position, adjust for screen texture location. Pass color
	out.lightPos = worldPos.xyz;
	out.xy = screenXY;
	out.uv = float2((1 + screenXY.x)/2,(1 - screenXY.y)/2);
	out.color = positions[iid].color;
	return out;
}

/*	fragment_illumination
 *
 *		Our color is ignored, but for debugging we echo the depth
 */

fragment float4 fragment_illumination(VertexOut v [[stage_in]],
							     constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]],
							     texture2d<float, access::sample> color [[texture(MXTextureIndexColor)]],
							     texture2d<float, access::sample> normal [[texture(MXTextureIndexNormal)]],
							     depth2d<float, access::sample> depth [[texture(MXTextureIndexDepth)]])
{
    constexpr sampler linearSampler (mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);

	float z = depth.sample(linearSampler, v.uv);
	float4 pos = float4(v.xy,z,1);
	float4 spos = u.vinverse * pos;
	float3 ppos = spos.xyz / spos.w;

	/*
	 *	Grab color, normal
	 */

	float3 teapotNormal = normalize(normal.sample(linearSampler,v.uv).xyz);

	/*
	 *	Find distance to the light
	 */

	float3 delta = v.lightPos - ppos;
	float r2 = dot(delta,delta) * 100;
	if (r2 < 1) r2 = 1;
	else r2 = 1/r2;
	if (r2 < 0.01) r2 = 0;

	float3 posvec = normalize(delta);
	float diffuse = clamp(dot(posvec,teapotNormal) * r2, 0, 1);

	return float4(v.color,diffuse);
}

