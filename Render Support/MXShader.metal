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
    float3 position	[[attribute(MXAttributeIndexPosition)]];
    float3 normal	[[attribute(MXAttributeIndexNormal)]];
};

struct VertexOut
{
	float4 position	[[position]];
	float3 normal;
};

/*	ScreenVertexIn
 *
 *		Screen vertices
 */

struct ScreenVertexIn
{
    float2 position	[[attribute(MXAttributeIndexPosition)]];
};

struct ScreenVertexOut
{
	float4 position [[position]];
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
	float4 nvect = float4(v.normal,0) * u.inverse;
	out.normal = normalize(nvect.xyz);

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

constant float3 lightColor(1,1,1);
constant float ambientIntensity = 0.1;
constant float3 lightDirection(1,0,1);
constant float3 eyeDirection(0,0,1);
constant float specularTightness = 25;
constant float specularIntensity = 0.75;

fragment float4 fragment_main(VertexOut v [[stage_in]],
							  constant float3 &objectColor [[buffer(MXFragmentIndexColor)]])
{
	const float3 normalLight = normalize(lightDirection);
	const float3 normalEye = normalize(eyeDirection);

	// Ambient lighting
	float4 ambient = float4(objectColor * lightColor * ambientIntensity,1.0);

	// Diffuse lighting
	float dotprod = dot(v.normal,normalLight);
	float diffuseIntensity = clamp(dotprod,0,1);
	float4 diffuse = float4(objectColor * lightColor * diffuseIntensity,1.0);

	// Specular lighting
	float3 refl = (2 * dotprod) * v.normal - normalLight;
	float specIntensity = dot(refl,normalEye);
	specIntensity = clamp(specIntensity,0,1);
	specIntensity = powr(specIntensity,specularTightness);
	float4 specular = float4(lightColor * specIntensity * specularIntensity,1.0);

	return ambient + diffuse + specular;
}

/****************************************************************************/
/*																			*/
/*	Screen Vertex Function													*/
/*																			*/
/****************************************************************************/

/*	vertex_screen
 *
 *		The vertex shader used to handle screen-sized processing using a 2D
 *	screen vertex
 */

vertex ScreenVertexOut vertex_screen(ScreenVertexIn v [[stage_in]])
{
	ScreenVertexOut out;
	out.position = float4(v.position,1,1);
	return out;
}

fragment float4 fragment_screen(ScreenVertexOut u [[stage_in]],
								constant float3 &objectColor [[buffer(MXFragmentIndexColor)]])
{
	return float4(objectColor,1);
}

fragment float4 output_fragment(ScreenVertexOut u [[stage_in]],
								texture2d<float, access::read> inColor [[texture(MXTextureIndexInColor)]])
{
	uint2 pos = (uint2)u.position.xy;
	return inColor.read(pos);
}

/****************************************************************************/
/*																			*/
/*	Layer Count Kernel														*/
/*																			*/
/****************************************************************************/

/*	layer_count
 *
 *		Layer count
 */

kernel void layer_count(texture2d<ushort, access::read> stencil [[texture(0)]],
						uint2 ix [[thread_position_in_grid]],
						device uint8_t *c [[buffer(1)]])
{
	ushort val = stencil.read(ix).x;
	if (c[ix.x] < val) c[ix.x] = val;
}

/****************************************************************************/
/*																			*/
/*	Compute Kernel															*/
/*																			*/
/****************************************************************************/

/*	layer_merge
 *
 *		Merge kernel
 */

kernel void layer_merge(texture2d<float, access::read> inColor [[texture(MXTextureIndexInColor)]],
						depth2d<float, access::read> inDepth [[texture(MXTextureIndexInDepth)]],
						texture2d<float, access::write> outColor [[texture(MXTextureIndexOutColor)]],
						texture2d<float, access::read_write> outDepth [[texture(MXTextureIndexOutDepth)]],
						uint2 index [[thread_position_in_grid]])
{
	float4 inc = inColor.read(index);
	float ind = inDepth.read(index);
	float curd = outDepth.read(index).r;

	if (ind < curd) {
		outDepth.write(ind,index);
		outColor.write(inc,index);
	}
}

/*	layer_cleardepth
 *
 *		Merge kernel
 */

kernel void layer_cleardepth(texture2d<float, access::write> outColor [[texture(MXTextureIndexOutColor)]],
							texture2d<float, access::write> outDepth [[texture(MXTextureIndexOutDepth)]],
						uint2 index [[thread_position_in_grid]])
{
	outColor.write(float4(0,0,0,1),index);
	outDepth.write(1.0,index);
}
