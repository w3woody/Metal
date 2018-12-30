//
//  MXShader.metal
//  Metal
//
//  Created by William Woody on 12/27/18.
//  Copyright © 2018 Glenview Software. All rights reserved.
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
	float4 color;
};

/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	vertex_main
 *
 *		The main vertex shader function used by our GPU. Here is where we would
 *	do geometry transformation options--but in our case we simply pass through
 *	our geometry.
 *
 *		There are two ways to access the individual vertices in our geometry.
 *	This uses one, where we declare a 'stage_in' parameter for the vertices
 *	in our geometry and set the attributes to signfiy which buffer holds
 *	our geometry.
 *
 *		The second is to declarae a [[vertex_id]] index as an index into an
 *	array containing all of the vertices.
 *
 *		Note that by default the range of our geometry is [-1,1] in X and Y.
 */

vertex VertexOut vertex_main(VertexIn v [[stage_in]],
							 constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]])
{
	VertexOut out;

	float4 worldPosition = u.model * float4(v.position,1.0);
	out.position = u.view * worldPosition;
	out.color = float4(v.normal,1.0);

	return out;
}

/*	fragment_main
 *
 *		The main fragment shader function used by our GPU. In general this would
 *	do the appropriate calculations to find the color of each of the pixels
 *	in our image. For this, we simply pass the results through.
 *
 *		Note that as we move from our vertex shader to our fragment shader,
 *	values that are not marked with the position attribute are simply
 *	interpolated. For complex operations such as texture mapping, this allows
 *	us to map textures with a little more effort.
 *
 *		Here, of course, we're boring and we just output the interpolated color.
 */

fragment float4 fragment_main(VertexOut v [[stage_in]])
{
	return v.color;
}
