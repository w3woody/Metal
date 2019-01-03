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

vertex VertexOut vertex_fairy(constant VertexIn *v [[buffer(MXVertexIndexVertices)]],
							  constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]],
							  constant FairyLightIn *positions [[buffer(MXVertexIndexLocations)]],
							  uint vid [[vertex_id]],
							  uint iid [[instance_id]])
{
	VertexOut out;

	// Pass through UV/color
	out.uv = (v[vid].position + 1)/2;
	out.color = positions[iid].color;

	// Transform location and offset
	float4 screenPos = u.view * u.model * float4(positions[iid].position,1.0);
	// Offset the X/Y location
	screenPos.xy += v[vid].position * 0.03 * positions[iid].size / screenPos.w;

	out.position = screenPos;
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
	float3 halfColor = v.color * c.x;
	return float4(halfColor,c.x);
}

