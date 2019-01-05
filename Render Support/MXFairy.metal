//
//  MXFairy.metal
//  Metal
//
//  Created by William Woody on 1/2/19.
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

struct VertexOut
{
	float4 position [[position]];
	float2 uv;
	float3 color;
};

/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	vertex_fairy
 *
 *		This is a stripped down version of the vertex_main function that is
 *	used for building our shadow map. We don't care about anything but the
 *	depth, so this skips initializing a bunch of stuff.
 */

vertex VertexOut vertex_fairy(VertexIn v [[stage_in]],
							  constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]],
							  constant MXFairyLocation *positions [[buffer(MXVertexIndexLocations)]],
							  uint iid [[instance_id]])
{
	VertexOut out;

	// Transform location and offset
	float4 screenPos = u.view * u.model * float4(positions[iid].position,1.0);
	// Offset the X/Y location
	float2 delta = v.position * 0.03 * positions[iid].size / screenPos.w;
	delta.x /= u.aspect;
	screenPos.xy += delta;
	out.position = screenPos;

	// Pass through UV/color
	out.uv = (v.position + 1)/2;
	out.color = positions[iid].color;
	return out;
}

/*	fragment_fairy
 *
 *		Our color is ignored, but for debugging we echo the depth
 */

fragment float4 fragment_fairy(VertexOut v [[stage_in]],
							 texture2d<float> fairyTexture [[ texture(MXTextureIndex0) ]])
{
	constexpr sampler linearSampler(mip_filter::linear,
									mag_filter::linear,
									min_filter::linear);

	float4 c = fairyTexture.sample(linearSampler,v.uv);
	float3 color = v.color * c.x;
	return float4(color,c.x);
}

