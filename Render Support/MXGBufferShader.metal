//
//  MXGBufferShader.metal
//  Metal
//
//  Created by William Woody on 1/3/19.
//  Copyright © 2019 Glenview Software. All rights reserved.
//

#include <metal_stdlib>
#include "MXShaderTypes.h"

using namespace metal;

/*
 *	This version of our shaders does the first half of the older shader
 *	functions, which is the geometry transformation and creating our GBuffer.
 */

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
	float4 shadow;
	float3 normal;
	float2 texture;
};

struct GBufferOut
{
	float4 color 	[[color(MXColorIndexColor)]];
	float4 normal 	[[color(MXColorIndexNormal)]];
};

/****************************************************************************/
/*																			*/
/*	Shaders																	*/
/*																			*/
/****************************************************************************/

/*	vertex_gbuffer
 *
 *		The main vertex shader function used by our GPU. Here is where we would
 *	do geometry transformation options--but in our case we simply pass through
 *	our geometry.
 */

vertex VertexOut vertex_gbuffer(VertexIn v [[stage_in]],
							    constant MXUniforms &u [[buffer(MXVertexIndexUniforms)]])
{
	VertexOut out;

	float4 worldPosition = u.model * float4(v.position,1.0);
	out.position = u.view * worldPosition;

	out.shadow = u.shadow * float4(v.position,1.0);

	float4 nvect = float4(v.normal,0) * u.inverse;
	out.normal = normalize(nvect.xyz);
	out.texture = v.texture;

	return out;
}

/*	fragment_gbuffer
 *
 *		This is our fragment gbuffer method. Instead of completely generating
 *	all of our lighting effects, instead we write to our color(0) channel the
 *	texture color of our teapot (with alpha set to 0 if our teapot is in the
 *	shadow), and the normal vector of our teapot writte in color(1).
 *
 *		These values are then used later to figure out the final rendered
 *	color of our teapot.
 */

fragment GBufferOut fragment_gbuffer(VertexOut v [[stage_in]],
							         texture2d<float, access::sample> texture [[texture(MXTextureIndex0)]],
							         depth2d<float, access::sample> shadowMap [[texture(MXTextureIndexShadow)]])
{
    constexpr sampler linearSampler (mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);

	/*
	 *	Pass in shadow depth texture for shadow mapping
	 *
	 *	Note that because we're using a perspective matrix we must correct
	 *	by dividing for w on each pixel. We must also remap our (x,y)
	 *	coordinate to deal with the fact that our geometry's coordinate
	 *	system runs [-1,1],[-1,1] from lower-left to upper-right, but
	 *	our texture coordinate system runs [0,1][0,1] from upper-left
	 *	to lower-right.
	 *
	 *	Note if we were representing a light at infinity, we would use
	 *	an orthographic transformation--meaning we would not have
	 *	to deal with dividing by w, since in an orthographic projection,
	 *	w = 1.
	 *
	 *	And if we were to do that, we can move most of the heavy lifting
	 *	for our texture coordinate transformation into the vertex shader.
	 */

	float x = (1 + v.shadow.x / v.shadow.w) / 2;
	float y = (1 - v.shadow.y / v.shadow.w) / 2;
	float depth = shadowMap.sample(linearSampler,float2(x,y));
	float zd = v.shadow.z / v.shadow.w - 0.001;

	/*
	 *	Generate the GBuffer
	 */

	GBufferOut out;

	// Texture color
	float3 teapotColor = texture.sample(linearSampler,v.texture).rgb;
	out.color = float4(teapotColor, (zd >= depth) ? 0 : 1);

	// Normal vector
	out.normal = float4(v.normal,0);

	return out;
}
