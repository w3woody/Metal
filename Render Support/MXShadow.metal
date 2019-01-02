//
//  MXShadow.metal
//  Metal
//
//  Created by William Woody on 1/1/19.
//  Copyright © 2019 Glenview Software. All rights reserved.
//
//	This is a stripped down vertex and fragment shader function set for
//	rendering our shadow map. Because we don't care about lighting and
//	stuff in this pass, we simply ignore most of what gets passed in.
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
 *	this **MUST MATCH** the declaration in MXGeometry for MXVertex.
 */

struct VertexIn {
    float3 position  [[attribute(MXAttributeIndexPosition)]];
    float3 normal    [[attribute(MXAttributeIndexNormal)]];
    float2 texture   [[attribute(MXAttributeIndexTexture)]];
};

struct VertexOut
{
	float4 position [[position]];
};

/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	vertex_shadow
 *
 *		This is a stripped down version of the vertex_main function that is
 *	used for building our shadow map. We don't care about anything but the
 *	depth, so this skips initializing a bunch of stuff.
 */

vertex VertexOut vertex_shadow(VertexIn v [[stage_in]],
							 constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]])
{
	VertexOut out;
	out.position = u.shadow * float4(v.position,1.0);
	return out;
}

/*	fragment_shadow
 *
 *		Our color is ignored, but for debugging we echo the depth
 */

fragment void fragment_shadow(VertexOut v [[stage_in]])
{
}

